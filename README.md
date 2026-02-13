# இஸ்லாமிய நூல்கள் — Tamil Islamic Library

A Flutter app for reading and listening to the **Quran** and **Hadith** in Tamil with offline AI-powered text-to-speech. TTS is driven by the **facebook/mms-tts-tam** VITS model running on-device via [MNN](https://github.com/alibaba/MNN).

## Project Structure

```
tamil-hadith-audio/
├── build_db.py              # Build SQLite database from cleaned text
├── clean.py                 # Text cleaning scripts
├── extract_hadith.py        # Extract hadiths from raw PDF text
├── tamil_hadith_app/        # Flutter application
│   ├── assets/
│   │   ├── db/
│   │   │   ├── hadith.db        # Bukhari + Muslim hadiths
│   │   │   └── tamil_ift.db     # Quran Tamil translation (IFT)
│   │   └── models/
│   │       └── tokens.txt       # TTS tokenizer vocabulary
│   ├── native/              # C++ MNN TTS wrapper (FFI)
│   │   ├── CMakeLists.txt
│   │   └── src/mnn_tts.cpp
│   ├── lib/
│   │   ├── main.dart
│   │   ├── theme.dart       # Islamic colour palette & Material 3 (light + dark)
│   │   ├── models/          # Data models (Hadith, QuranVerse)
│   │   ├── screens/         # UI screens (9 screens)
│   │   ├── services/        # TTS engine, tokenizer, DB, audio, settings
│   │   └── widgets/
│   └── 3rd_party/MNN/       # MNN source (built from source for Android)
└── utils/
```

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | ≥ 3.10 |
| Android SDK | compileSdk matching Flutter default |
| Android NDK | matching Flutter default |
| CMake | ≥ 3.22.1 |
| Python | 3.x (only for data preparation) |

## Quick Start

### 1. Clone the repo

```bash
git clone <repo-url>
cd tamil-hadith-audio
```

### 2. Prepare assets (one-time)

The database and model are already in `tamil_hadith_app/assets/`. If you need to rebuild:

```bash
# Create / activate Python venv
python3 -m venv venv && source venv/bin/activate

# Build the hadith database from cleaned text
python build_db.py

# Copy database into Flutter assets
cp bukhari.db tamil_hadith_app/assets/db/
```

### 3. Get Flutter dependencies

```bash
cd tamil_hadith_app
flutter pub get
```

### 4. Run the app

**Android (debug):**

```bash
flutter run --debug
```

> The first build will compile MNN from source via CMake — this takes a few minutes.

**Release build:**

```bash
flutter build apk --release
```

The APK is written to `tamil_hadith_app/build/app/outputs/flutter-apk/app-release.apk`.

### 5. Run on a specific device

```bash
# List connected devices
flutter devices

# Run on a specific device
flutter run -d <device-id>
```

## Features

### 📖 Quran (குர்ஆன்)
- Complete Tamil translation of all **114 suras** & **6,236 verses**
- Sura-by-sura browsing with verse list navigation
- Whole-sura playback — plays all verses sequentially with lookahead prefetch
- Full-text search across all verses
- Translation source: [alqurandb.com](https://alqurandb.com/api/translations/download/tamil_ift/sqlite) (IFT)

### 📚 Hadith (ஹதீஸ்)
- **Sahih al-Bukhari** — 7,393 hadiths across 97 books
- **Sahih Muslim** — 5,770 hadiths across 56 books
- Book-based browsing with paginated hadith lists
- Chapter headings, narrator info, and hadith text in Tamil
- Full-text search across both collections

### 🔊 AI Text-to-Speech
- On-device Tamil TTS using **MNN** (Mobile Neural Network) inference
- Based on **facebook/mms-tts-tam** VITS model, INT8 quantised for mobile
- C++ native code via FFI for maximum performance
- Streaming synthesis — audio starts playing before full generation completes
- Background isolate processing to keep UI smooth
- Adjustable TTS speed (0.7×–1.6×) and pitch (0.5×–1.5×)

### 💾 Offline-First
- All text content stored in local **SQLite** databases
- Audio cache with LRU eviction (1 GB max) — listen once, play instantly again
- TTS model downloaded once via onboarding, runs entirely on-device
- No internet required after initial setup

### ⚙️ Settings
- **Dark mode** toggle (System / Light / Dark)
- **TTS speed & pitch** sliders
- **Language** selector (Tamil / English)
- Model management (download / delete / switch INT8 ↔ FP16)
- Audio cache management

### 🔖 Bookmarks
- Save favourite hadiths and verses for quick access
- Cross-collection bookmarking

## How It Works

1. **Database** — Hadith and Quran Tamil translations are stored in two SQLite databases (`hadith.db`, `tamil_ift.db`), loaded at startup.
2. **UI** — Browse Quran by sura or Hadith by book, view details, read text, and search.
3. **TTS** — When the user taps play, the Tamil text is:
   - **Tokenized** character-by-character using the MMS-TTS-TAM vocabulary
   - **Chunked** into sentence-sized pieces (≤ 800 tokens each) to avoid blocking the UI
   - **Synthesized** on-device by the VITS model running through MNN (C++ via FFI)
   - **Played back** as 16 kHz mono PCM audio
4. **Settings** — Theme, voice speed/pitch, and language preferences are persisted via `SharedPreferences` and applied reactively.

## Native Build (MNN)

The native TTS wrapper is built automatically by the Flutter/Gradle CMake integration. MNN is compiled from source under `3rd_party/MNN/` with these options:

- CPU-only (no OpenCL/Vulkan)
- ARM FP16 enabled (`MNN_ARM82`)
- Shared library (`libmnn_tts.so`)

No manual native build step is needed — `flutter run` handles everything.

## Data Sources

| Data | Source |
|------|--------|
| Quran Tamil Translation | [alqurandb.com — IFT](https://alqurandb.com/api/translations/download/tamil_ift/sqlite) |
| Hadith Collections | Sahih al-Bukhari & Sahih Muslim (Tamil) |
| TTS Model | [facebook/mms-tts-tam](https://huggingface.co/facebook/mms-tts-tam) via MNN |

## Troubleshooting

| Issue | Fix |
|-------|-----|
| CMake not found | Install CMake ≥ 3.22.1 via Android Studio SDK Manager |
| NDK not found | Set `ANDROID_NDK_HOME` or install NDK via SDK Manager |
| Model download fails | Check internet connection; retry from Settings |
| ANR on long text | Already handled — text is chunked before synthesis |
