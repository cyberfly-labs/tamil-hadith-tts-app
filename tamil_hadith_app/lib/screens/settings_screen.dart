import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/model_download_service.dart';
import '../screens/hadith_detail_screen.dart';

/// Settings screen — model selection, cache management, app info.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ModelDownloadService _downloadService = ModelDownloadService();

  bool _loading = true;
  TtsModelVariant _selected = TtsModelVariant.int8;
  final Map<TtsModelVariant, bool> _downloaded = {};
  final Map<TtsModelVariant, int> _sizes = {};

  // Download state
  TtsModelVariant? _downloading;
  double _downloadProgress = 0;
  String _downloadStatus = '';

  int _cachedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    await _downloadService.initialize();
    _selected = _downloadService.selectedVariant;

    for (final v in TtsModelVariant.values) {
      _downloaded[v] = await _downloadService.isVariantDownloaded(v);
      _sizes[v] = await _downloadService.variantSize(v);
    }

    _cachedCount = await sharedAudioCache.getCachedCount();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _selectModel(TtsModelVariant variant) async {
    if (variant == _selected) return;
    HapticFeedback.selectionClick();

    // If not downloaded yet, download first
    if (_downloaded[variant] != true) {
      await _downloadVariant(variant);
      if (_downloaded[variant] != true) return; // download failed / cancelled
    }

    await _downloadService.setSelectedVariant(variant);

    // Restart TTS engine with new model
    sharedTtsEngine.dispose();

    setState(() => _selected = variant);

    // Re-init the engine in background
    await sharedTtsEngine.initialize();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${variant.label} மாதிரி பயன்படுத்தப்படுகிறது'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _downloadVariant(TtsModelVariant variant) async {
    setState(() {
      _downloading = variant;
      _downloadProgress = 0;
      _downloadStatus = 'பதிவிறக்கம் தொடங்குகிறது...';
    });

    try {
      await _downloadService.downloadModel(
        variant: variant,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            if (total > 0) {
              _downloadProgress = received / total;
              final rMB = (received / (1024 * 1024)).toStringAsFixed(1);
              final tMB = (total / (1024 * 1024)).toStringAsFixed(0);
              _downloadStatus = '$rMB / $tMB MB';
            } else {
              _downloadStatus =
                  '${(received / (1024 * 1024)).toStringAsFixed(1)} MB...';
            }
          });
        },
      );

      _downloaded[variant] = true;
      _sizes[variant] = await _downloadService.variantSize(variant);
    } on SocketException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('இணைய இணைப்பு இல்லை'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('பதிவிறக்க பிழை: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _deleteVariant(TtsModelVariant variant) async {
    if (variant == _selected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('தற்போது பயன்பாட்டில் உள்ள மாதிரியை நீக்க முடியாது'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('மாதிரியை நீக்கவா?'),
        content: Text('${variant.label} (${variant.sizeMB} MB) நீக்கப்படும்.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ரத்து')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('நீக்கு')),
        ],
      ),
    );

    if (confirm != true) return;

    await _downloadService.deleteVariant(variant);
    _downloaded[variant] = false;
    _sizes[variant] = 0;
    if (mounted) setState(() {});
  }

  Future<void> _clearAudioCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ஒலி தற்காலிக சேமிப்பை அழிக்கவா?'),
        content: Text('$_cachedCount ஹதீஸ் ஒலிக் கோப்புகள் நீக்கப்படும்.\n'
            'அடுத்த முறை மீண்டும் உருவாக்கப்படும்.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ரத்து')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('அழி')),
        ],
      ),
    );

    if (confirm != true) return;

    await sharedAudioCache.clearCache();
    _cachedCount = 0;
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ஒலி தற்காலிக சேமிப்பு அழிக்கப்பட்டது'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('அமைப்புகள்')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── Model selection section ──
                const _SectionHeader(title: 'AI ஒலி மாதிரி'),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'சிறிய மாதிரி வேகமாக பதிவிறக்கம் ஆகும். '
                    'பெரிய மாதிரி சிறந்த ஒலித்தரம் கொடுக்கும்.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B6B6B),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                for (final variant in TtsModelVariant.values)
                  _ModelCard(
                    variant: variant,
                    isSelected: variant == _selected,
                    isDownloaded: _downloaded[variant] ?? false,
                    sizeOnDisk: _sizes[variant] ?? 0,
                    isDownloading: _downloading == variant,
                    downloadProgress: _downloading == variant ? _downloadProgress : 0,
                    downloadStatus: _downloading == variant ? _downloadStatus : '',
                    onSelect: () => _selectModel(variant),
                    onDelete: () => _deleteVariant(variant),
                  ),

                const SizedBox(height: 24),

                // ── Cache section ──
                const _SectionHeader(title: 'தற்காலிக சேமிப்பு'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE8DDD0)),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.cached_rounded, color: Color(0xFF1B4D3E)),
                        title: const Text('ஒலி தற்காலிக சேமிப்பு'),
                        subtitle: Text('$_cachedCount ஹதீஸ்கள் சேமிக்கப்பட்டுள்ளன'),
                        trailing: TextButton(
                          onPressed: _cachedCount > 0 ? _clearAudioCache : null,
                          child: const Text('அழி'),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── About section ──
                const _SectionHeader(title: 'பயன்பாடு பற்றி'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFDF9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE8DDD0)),
                    ),
                    child: const Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.auto_stories_rounded, color: Color(0xFF1B4D3E)),
                          title: Text('புகாரி ஹதீஸ் — AI தமிழ் ஒலி'),
                          subtitle: Text('பதிப்பு 1.0.0'),
                        ),
                        Divider(height: 0),
                        ListTile(
                          leading: Icon(Icons.memory_rounded, color: Color(0xFF1B4D3E)),
                          title: Text('AI மாதிரி'),
                          subtitle: Text('facebook/mms-tts-tam (MNN)'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Helper widgets
// ══════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFFD4A04A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B4D3E),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final TtsModelVariant variant;
  final bool isSelected;
  final bool isDownloaded;
  final int sizeOnDisk;
  final bool isDownloading;
  final double downloadProgress;
  final String downloadStatus;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _ModelCard({
    required this.variant,
    required this.isSelected,
    required this.isDownloaded,
    required this.sizeOnDisk,
    required this.isDownloading,
    required this.downloadProgress,
    required this.downloadStatus,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isDownloading ? null : onSelect,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFD4A04A)
                    : const Color(0xFFE8DDD0),
                width: isSelected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Radio indicator
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected
                          ? const Color(0xFF1B4D3E)
                          : const Color(0xFF9E9E9E),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            variant.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            variant.description,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B6B6B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Size badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A04A).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFD4A04A).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        '~${variant.sizeMB} MB',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB8860B),
                        ),
                      ),
                    ),
                  ],
                ),

                // Download progress bar
                if (isDownloading) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: downloadProgress > 0 ? downloadProgress : null,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE8DDD0),
                      color: const Color(0xFF1B4D3E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    downloadStatus,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B6B6B),
                    ),
                  ),
                ],

                // Status row
                if (!isDownloading) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 32), // align with text above
                      if (isDownloaded)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 14, color: Colors.green.shade600),
                            const SizedBox(width: 4),
                            Text(
                              'பதிவிறக்கப்பட்டது '
                              '(${(sizeOnDisk / (1024 * 1024)).toStringAsFixed(0)} MB)',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ],
                        )
                      else
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_download_outlined,
                                size: 14, color: Color(0xFF9E9E9E)),
                            SizedBox(width: 4),
                            Text(
                              'பதிவிறக்கம் தேவை',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9E9E9E),
                              ),
                            ),
                          ],
                        ),
                      const Spacer(),
                      // Delete button (only if downloaded and not active)
                      if (isDownloaded && !isSelected)
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 18, color: Colors.red.shade400),
                          onPressed: onDelete,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'நீக்கு',
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
