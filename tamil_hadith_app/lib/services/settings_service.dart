import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized, reactive settings service.
///
/// Persists user preferences (theme, TTS speed/pitch) via
/// SharedPreferences and exposes a [ValueNotifier] so the MaterialApp
/// can rebuild when the theme changes.
class SettingsService extends ChangeNotifier {
  // ── Singleton ──
  static final SettingsService _instance = SettingsService._();
  factory SettingsService() => _instance;
  SettingsService._();

  static const String _keyThemeMode = 'theme_mode';
  static const String _keyTtsSpeed = 'tts_speed';
  static const String _keyTtsPitch = 'tts_pitch';

  bool _initialized = false;
  late SharedPreferences _prefs;

  // ── Theme ──
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  // ── TTS ──
  double _ttsSpeed = 1.15; // default lengthScale
  double get ttsSpeed => _ttsSpeed;

  double _ttsPitch = 1.0;
  double get ttsPitch => _ttsPitch;

  /// Initialize — call once from main().
  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();

    _themeMode = _parseThemeMode(_prefs.getString(_keyThemeMode));
    _ttsSpeed = _prefs.getDouble(_keyTtsSpeed) ?? 1.15;
    _ttsPitch = _prefs.getDouble(_keyTtsPitch) ?? 1.0;

    _initialized = true;
  }

  // ── Setters (persist + notify) ──

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    await _prefs.setString(_keyThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setTtsSpeed(double speed) async {
    _ttsSpeed = speed;
    await _prefs.setDouble(_keyTtsSpeed, speed);
    notifyListeners();
  }

  Future<void> setTtsPitch(double pitch) async {
    _ttsPitch = pitch;
    await _prefs.setDouble(_keyTtsPitch, pitch);
    notifyListeners();
  }

  // ── Helpers ──

  static ThemeMode _parseThemeMode(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
