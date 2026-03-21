import 'package:flutter/material.dart';

import '../models/quran_verse.dart';
import '../theme.dart';

class QuranTafsirScreen extends StatelessWidget {
  final QuranVerse verse;

  const QuranTafsirScreen({super.key, required this.verse});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasTafsir = verse.tafsir.trim().isNotEmpty;
    final scaffoldColor = theme.scaffoldBackgroundColor;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.surface;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.warmBorder;
    final bodyTextColor = isDark ? const Color(0xFFF5F0E8) : AppTheme.darkText;
    final secondaryTextColor =
        isDark ? AppTheme.darkSubtle : AppTheme.subtleText;
    final accentBackground = isDark
        ? AppTheme.darkEmerald.withValues(alpha: 0.16)
        : AppTheme.emerald.withValues(alpha: 0.08);
    final accentBorder = isDark
        ? AppTheme.darkGold.withValues(alpha: 0.25)
        : AppTheme.gold.withValues(alpha: 0.35);

    return Scaffold(
      appBar: AppBar(
        title: Text('தஃப்ஸீர் ${verse.sura}:${verse.aya}'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: isDark ? 0.08 : 0.04),
              scaffoldColor,
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.03),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${SuraNames.getName(verse.sura)} • ${verse.aya}',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkGold : AppTheme.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'வசனம்',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 0.2,
                        fontWeight: FontWeight.w700,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      verse.text,
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.9,
                        color: bodyTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: accentBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'முக்தஸர் தஃப்ஸீர்',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (hasTafsir)
                      SelectableText(
                        verse.tafsir,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.95,
                          color: bodyTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.cardColor.withValues(alpha: isDark ? 0.35 : 0.8),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'இந்த வசனத்திற்கு தஃப்ஸீர் இல்லை.',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.7,
                            color: secondaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (hasTafsir) ...[
                      const SizedBox(height: 14),
                      Text(
                        'நீண்டதாக இருந்தால் உரையை நீண்ட நேரம் அழுத்தி தேர்வு செய்து நகலெடுக்கலாம்.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: secondaryTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasTafsir) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'எழுத்து தெளிவாக இருக்க இந்தப் பக்கத்தில் உயர்ந்த வரி இடைவெளியும் அதிகமான எதிரொலி நிறங்களும் பயன்படுத்தப்பட்டுள்ளன.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.65,
                            color: secondaryTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
