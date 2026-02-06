import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/hadith_database.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize database
  final database = HadithDatabase();
  await database.initialize();

  runApp(TamilHadithApp(database: database));
}

class TamilHadithApp extends StatelessWidget {
  final HadithDatabase database;

  const TamilHadithApp({super.key, required this.database});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'புகாரி ஹதீஸ்',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: HomeScreen(database: database),
    );
  }
}


