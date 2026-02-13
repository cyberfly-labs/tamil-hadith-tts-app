# இஸ்லாமிய நூல்கள் — Tamil Islamic Library

A Flutter app for reading and listening to the **Quran** and **Hadith** in Tamil with offline AI-powered text-to-speech.

## Features

### 📖 Quran (குர்ஆன்)
- Complete Tamil translation of all **114 suras** and **6,236 verses**
- Sura-by-sura browsing with verse list navigation
- **Whole-sura playback** — plays all verses sequentially with lookahead prefetch
- Full-text search across all verses
- Translation source: [alqurandb.com](https://alqurandb.com/api/translations/download/tamil_ift/sqlite) (IFT)

### 📚 Hadith (ஹதீஸ்)
- **Sahih al-Bukhari** — 7,393 hadiths across 97 books
- **Sahih Muslim** — 5,770 hadiths across 56 books
- Book-based browsing with paginated hadith lists
- Chapter headings, narrator info, and hadith text in Tamil
- Full-text search across both collections

### 🔊 AI Text-to-Speech
- On-device Tamil TTS using **MNN** (Mobile Neural Network) inference engine
- Based on **facebook/mms-tts-tam** VITS model, INT8 quantised for mobile
- C++ native code via FFI for maximum performance
- Streaming synthesis — audio starts playing before full generation completes
- Background isolate processing to keep UI smooth
- Adjustable TTS speed (0.7×–1.6×) and pitch (0.5×–1.5×)

### 💾 Offline-First
- All text content stored in local **SQLite** databases (hadith.db, tamil_ift.db)
- Audio cache with LRU eviction (1 GB max) — listen once, play instantly again
- TTS model downloaded once via onboarding, runs entirely on-device
- No internet required after initial setup

### ⚙️ Settings
- **Dark mode** toggle (System / Light / Dark)
- **TTS speed & pitch** sliders with live preview
- **Language** selector (Tamil / English)
- AI model management (download / delete / switch INT8 ↔ FP16+INT8)
- Audio cache management with clear option

### 🔖 Bookmarks
- Save favourite hadiths and verses for quick access
- Cross-collection bookmarking (Bukhari & Muslim)

### 🎨 Design
- Islamic-themed UI with emerald and gold palette
- Material 3 with warm borders and elegant typography
- Responsive font sizing controls on detail screens
- Full light & dark theme support with animated transitions

## Architecture

```
lib/
├── main.dart                      # App entry, DB & audio session init
├── theme.dart                     # Islamic colour palette & Material 3 theme
├── models/
│   ├── hadith.dart                # Hadith & HadithCollection models
│   └── quran_verse.dart           # Sura & Verse models
├── screens/
│   ├── home_screen.dart           # Bottom nav (Quran / Hadith tabs)
│   ├── hadith_list_screen.dart
│   ├── hadith_detail_screen.dart
│   ├── bookmarks_screen.dart
│   ├── quran_sura_list_screen.dart
│   ├── quran_verse_list_screen.dart
│   ├── quran_verse_detail_screen.dart
│   ├── settings_screen.dart       # Theme, TTS, model, cache, language
│   └── onboarding_screen.dart     # First-launch model download
├── services/
│   ├── tts_engine.dart            # Dart ↔ C++ FFI bridge
│   ├── tts_isolate.dart           # Background isolate for synthesis
│   ├── mnn_tts_bindings.dart      # FFI bindings for native MNN TTS
│   ├── audio_player_service.dart  # Streaming chunk-based playback
│   ├── audio_cache_service.dart   # LRU WAV file cache
│   ├── hadith_database.dart
│   ├── quran_database.dart
│   ├── bookmark_service.dart
│   ├── model_download_service.dart
│   ├── settings_service.dart      # Theme, TTS speed/pitch, locale prefs
│   ├── precache_service.dart      # Lookahead audio prefetching
│   └── tokenizer.dart             # Tamil text tokenizer for TTS
native/
├── CMakeLists.txt
└── src/
    ├── mnn_tts.cpp                # C++ VITS inference via MNN
    └── mnn_tts.h
3rd_party/
└── MNN/                           # MNN inference framework
assets/
├── db/
│   ├── hadith.db                  # Bukhari + Muslim hadiths
│   └── tamil_ift.db               # Quran Tamil translation
└── models/
    └── tokens.txt                 # TTS tokenizer vocabulary
```

## Requirements

- Flutter SDK ≥ 3.10
- Android NDK (for native C++ build)
- ~50 MB for TTS model download (INT8 quantized)

## Getting Started

```bash
cd tamil_hadith_app
flutter pub get
flutter run
```

On first launch, the app will prompt to download the TTS model (~28–55 MB). After that, everything works offline.

## Data Sources

| Data | Source |
|------|--------|
| Quran Tamil Translation | [alqurandb.com — IFT](https://alqurandb.com/api/translations/download/tamil_ift/sqlite) |
| Hadith Collections | Sahih al-Bukhari & Sahih Muslim (Tamil) |
| TTS Model | [facebook/mms-tts-tam](https://huggingface.co/facebook/mms-tts-tam) via MNN |

## License

Private project — not published to pub.dev.
