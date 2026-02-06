import 'dart:io';

import 'package:flutter/material.dart';

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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('அமைப்புகள்')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── Model selection section ──
                _SectionHeader(title: 'AI ஒலி மாதிரி', color: cs),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'சிறிய மாதிரி வேகமாக பதிவிறக்கம் ஆகும். '
                    'பெரிய மாதிரி சிறந்த ஒலித்தரம் கொடுக்கும்.',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.5),
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
                    cs: cs,
                  ),

                const SizedBox(height: 24),

                // ── Cache section ──
                _SectionHeader(title: 'தற்காலிக சேமிப்பு', color: cs),
                ListTile(
                  leading: Icon(Icons.cached_rounded, color: cs.primary),
                  title: const Text('ஒலி தற்காலிக சேமிப்பு'),
                  subtitle: Text('$_cachedCount ஹதீஸ்கள் சேமிக்கப்பட்டுள்ளன'),
                  trailing: TextButton(
                    onPressed: _cachedCount > 0 ? _clearAudioCache : null,
                    child: const Text('அழி'),
                  ),
                ),

                const SizedBox(height: 24),

                // ── About section ──
                _SectionHeader(title: 'பயன்பாடு பற்றி', color: cs),
                const ListTile(
                  leading: Icon(Icons.auto_stories_rounded),
                  title: Text('புகாரி ஹதீஸ் — AI தமிழ் ஒலி'),
                  subtitle: Text('பதிப்பு 1.0.0'),
                ),
                const ListTile(
                  leading: Icon(Icons.memory_rounded),
                  title: Text('AI மாதிரி'),
                  subtitle: Text('facebook/mms-tts-tam (MNN)'),
                ),
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
  final ColorScheme color;

  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color.primary,
          letterSpacing: 0.5,
        ),
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
  final ColorScheme cs;

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
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isSelected
              ? BorderSide(color: cs.primary, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: isDownloading ? null : onSelect,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
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
                      color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.3),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            variant.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            variant.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Size badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '~${variant.sizeMB} MB',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.6),
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
                      backgroundColor: cs.surfaceContainerHighest,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    downloadStatus,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_download_outlined,
                                size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
                            const SizedBox(width: 4),
                            Text(
                              'பதிவிறக்கம் தேவை',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      const Spacer(),
                      // Delete button (only if downloaded and not active)
                      if (isDownloaded && !isSelected)
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 18, color: cs.error),
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
