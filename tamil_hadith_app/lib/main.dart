import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_session/audio_session.dart';

import 'services/hadith_database.dart';
import 'services/quran_database.dart';
import 'services/model_download_service.dart';
import 'services/bookmark_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Configure audio session for speech playback (continues when screen off)
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());

  // Initialize databases
  final hadithDatabase = HadithDatabase();
  final quranDatabase = QuranDatabase();
  await Future.wait([
    hadithDatabase.initialize(),
    quranDatabase.initialize(),
  ]);

  // Initialize bookmark service
  final bookmarkService = BookmarkService();
  await bookmarkService.initialize();
  await bookmarkService.loadBookmarks();

  // Check if model is already downloaded
  final modelService = ModelDownloadService();
  await modelService.initialize();
  final modelReady = await modelService.isModelDownloaded;

  runApp(TamilHadithApp(
    hadithDatabase: hadithDatabase,
    quranDatabase: quranDatabase,
    modelReady: modelReady,
  ));
}

class TamilHadithApp extends StatelessWidget {
  final HadithDatabase hadithDatabase;
  final QuranDatabase quranDatabase;
  final bool modelReady;

  const TamilHadithApp({
    super.key,
    required this.hadithDatabase,
    required this.quranDatabase,
    required this.modelReady,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'இஸ்லாமிய நூல்கள்',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: modelReady
          ? HomeScreen(
              hadithDatabase: hadithDatabase,
              quranDatabase: quranDatabase,
            )
          : _OnboardingWrapper(
              hadithDatabase: hadithDatabase,
              quranDatabase: quranDatabase,
            ),
    );
  }
}

/// Wrapper that shows onboarding, then navigates to home when done.
class _OnboardingWrapper extends StatelessWidget {
  final HadithDatabase hadithDatabase;
  final QuranDatabase quranDatabase;

  const _OnboardingWrapper({
    required this.hadithDatabase,
    required this.quranDatabase,
  });

  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(
      onComplete: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              hadithDatabase: hadithDatabase,
              quranDatabase: quranDatabase,
            ),
          ),
        );
      },
    );
  }
}
