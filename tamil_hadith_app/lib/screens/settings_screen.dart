import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';
import '../screens/hadith_detail_screen.dart';

/// Settings screen — theme, TTS controls, model selection, cache, about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();

  bool _loading = true;

  int _cachedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    _cachedCount = await sharedAudioCache.getCachedCount();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _clearAudioCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ஒலி தற்காலிக சேமிப்பை அழிக்கவா?'),
        content: Text(
          '$_cachedCount ஹதீஸ் ஒலிக் கோப்புகள் நீக்கப்படும்.\n'
          'அடுத்த முறை மீண்டும் உருவாக்கப்படும்.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ரத்து'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('அழி'),
          ),
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

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFFFFDF9);
    final borderColor = isDark
        ? const Color(0xFF2E2E2E)
        : const Color(0xFFE8DDD0);
    final emerald = isDark ? const Color(0xFF7A5D08) : const Color(0xFFB8860B);
    final gold = isDark ? const Color(0xFFFFD54F) : const Color(0xFF3E2723);
    final subtleText = isDark
        ? const Color(0xFF9E9E9E)
        : const Color(0xFF6B6B6B);

    return Scaffold(
      appBar: AppBar(title: const Text('அமைப்புகள்')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
              children: [
                // ══════════════════════════════════════════
                // 1. Appearance
                // ══════════════════════════════════════════
                _SectionHeader(title: 'தோற்றம்', icon: Icons.palette_outlined),
                const SizedBox(height: 8),
                _SettingsCard(
                  cardColor: cardColor,
                  borderColor: borderColor,
                  children: [
                    _ThemeSelector(
                      current: _settings.themeMode,
                      emerald: emerald,
                      gold: gold,
                      onChanged: (mode) async {
                        HapticFeedback.selectionClick();
                        await _settings.setThemeMode(mode);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ══════════════════════════════════════════
                // 2. Cache & Storage
                // ══════════════════════════════════════════
                _SectionHeader(title: 'சேமிப்பு', icon: Icons.storage_rounded),
                const SizedBox(height: 8),
                _SettingsCard(
                  cardColor: cardColor,
                  borderColor: borderColor,
                  children: [
                    ListTile(
                      leading: Icon(Icons.cached_rounded, color: emerald),
                      title: const Text('ஒலி தற்காலிக சேமிப்பு'),
                      subtitle: Text(
                        '$_cachedCount ஹதீஸ்கள் சேமிக்கப்பட்டுள்ளன',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: _cachedCount > 0 ? _clearAudioCache : null,
                        child: const Text('அழி'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ══════════════════════════════════════════
                // 6. About
                // ══════════════════════════════════════════
                _SectionHeader(
                  title: 'பயன்பாடு பற்றி',
                  icon: Icons.info_outline_rounded,
                ),
                const SizedBox(height: 8),
                _SettingsCard(
                  cardColor: cardColor,
                  borderColor: borderColor,
                  children: [
                    ListTile(
                      leading: Icon(Icons.auto_stories_rounded, color: emerald),
                      title: const Text('இஸ்லாமிய நூல்கள் — AI தமிழ் ஒலி'),
                      subtitle: const Text('பதிப்பு 1.0.0'),
                    ),
                    Divider(height: 0, color: borderColor),
                    ListTile(
                      leading: Icon(Icons.memory_rounded, color: emerald),
                      title: const Text('AI மாதிரி'),
                      subtitle: const Text('facebook/mms-tts-tam (MNN)'),
                      trailing: Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: subtleText,
                      ),
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://huggingface.co/developerabu/mms-tts-tam-mnn',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    Divider(height: 0, color: borderColor),
                    ListTile(
                      leading: Icon(Icons.menu_book_rounded, color: emerald),
                      title: const Text('குர்ஆன் தமிழ் மொழிபெயர்ப்பு'),
                      subtitle: const Text('alqurandb.com (IFT)'),
                      trailing: Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: subtleText,
                      ),
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://alqurandb.com/api/translations/download/tamil_ift/sqlite',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Helper widgets
// ══════════════════════════════════════════════════════════════

/// Section header with gold accent bar and icon.
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald = isDark ? const Color(0xFF7A5D08) : const Color(0xFFB8860B);
    final gold = isDark ? const Color(0xFFFFD54F) : const Color(0xFF3E2723);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: gold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 18, color: emerald),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: emerald,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded card wrapper.
class _SettingsCard extends StatelessWidget {
  final Color cardColor;
  final Color borderColor;
  final List<Widget> children;

  const _SettingsCard({
    required this.cardColor,
    required this.borderColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Theme mode selector — 3 segmented options.
class _ThemeSelector extends StatelessWidget {
  final ThemeMode current;
  final Color emerald;
  final Color gold;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeSelector({
    required this.current,
    required this.emerald,
    required this.gold,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.brightness_6_rounded, size: 20, color: emerald),
              const SizedBox(width: 10),
              const Text(
                'தீம்',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ThemeChip(
                icon: Icons.phone_android_rounded,
                label: 'சாதனம்',
                selected: current == ThemeMode.system,
                emerald: emerald,
                onTap: () => onChanged(ThemeMode.system),
              ),
              const SizedBox(width: 8),
              _ThemeChip(
                icon: Icons.light_mode_rounded,
                label: 'ஒளி',
                selected: current == ThemeMode.light,
                emerald: emerald,
                onTap: () => onChanged(ThemeMode.light),
              ),
              const SizedBox(width: 8),
              _ThemeChip(
                icon: Icons.dark_mode_rounded,
                label: 'இருள்',
                selected: current == ThemeMode.dark,
                emerald: emerald,
                onTap: () => onChanged(ThemeMode.dark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color emerald;
  final VoidCallback onTap;

  const _ThemeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.emerald,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveBorder = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final inactiveColor = isDark ? Colors.grey.shade400 : Colors.grey;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? emerald.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? emerald : inactiveBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, size: 22, color: selected ? emerald : inactiveColor),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? emerald : inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
