import 'package:flutter/foundation.dart';

import '../models/hadith.dart';
import 'audio_cache_service.dart';
import 'hadith_database.dart';
import 'tts_engine.dart';

/// Pre-caches the first N hadith audio files in the background
/// so the user gets instant playback on their very first tap.
///
/// Runs after onboarding completes, yields to the UI between each synthesis.
class PreCacheService {
  /// How many hadiths to pre-cache after install.
  static const int preCacheCount = 10;

  static bool _running = false;

  /// Kick off background pre-caching. Safe to call multiple times —
  /// subsequent calls are no-ops if already running.
  static Future<void> preCacheFirstHadiths({
    required HadithDatabase db,
    required TtsEngine engine,
    required AudioCacheService cache,
  }) async {
    if (_running) return;
    _running = true;

    try {
      if (!engine.isInitialized) {
        await engine.initialize();
      }
      if (!engine.isNativeAvailable) {
        debugPrint('PreCache: native engine not available, skipping');
        return;
      }

      await cache.initialize();

      // Fetch the first N hadiths from Bukhari book 1
      final hadiths = await db.getHadithsPaginated(
        collection: HadithCollection.bukhari,
        bookNumber: 1,
        offset: 0,
        limit: preCacheCount,
      );

      int cached = 0;
      for (final hadith in hadiths) {
        // Skip if already cached
        if (cache.isCachedByKey(hadith.cacheKey)) {
          cached++;
          continue;
        }

        try {
          final audio = await engine.synthesize(hadith.textTamil);
          if (audio != null && audio.isNotEmpty) {
            await cache.saveToCacheByKey(hadith.cacheKey, audio);
            cached++;
            debugPrint('PreCache: $cached/$preCacheCount '
                '(${hadith.cacheKey})');
          }
        } catch (e) {
          debugPrint('PreCache: failed ${hadith.cacheKey}: $e');
          // Continue with the next one — don't break the whole loop
        }

        // Yield to the UI thread between each heavy synthesis
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      debugPrint('PreCache: done — $cached/$preCacheCount hadiths cached');
    } catch (e) {
      debugPrint('PreCache: fatal error: $e');
    } finally {
      _running = false;
    }
  }
}
