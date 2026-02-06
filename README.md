# Tamil Hadith Audio (புகாரி ஹதீஸ்)

A Flutter app for reading and listening to Sahih al-Bukhari hadiths in Tamil. Text-to-speech is powered by the **facebook/mms-tts-tam** VITS model running on-device via [MNN](https://github.com/alibaba/MNN).

## Project Structure

```
tamil-hadith-audio/
├── build_db.py              # Build SQLite database from cleaned text
├── clean.py                 # Text cleaning scripts
├── extract_hadith.py        # Extract hadiths from raw PDF text
├── model_fp16_int8.mnn      # Quantised VITS model (fp16 weights, int8 activations)
├── tokens.txt               # Tokenizer vocabulary
├── tamil_hadith_app/        # Flutter application
│   ├── assets/
│   │   ├── db/bukhari.db    # Pre-built hadith database
│   │   └── models/          # MNN model + vocab bundled as assets
│   ├── native/              # C++ MNN TTS wrapper (FFI)
│   │   ├── CMakeLists.txt
│   │   └── src/mnn_tts.cpp
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/          # Data models
│   │   ├── screens/         # UI screens
│   │   ├── services/        # TTS engine, tokenizer, DB, audio player
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

## How It Works

1. **Database** — Sahih al-Bukhari hadiths in Tamil are stored in a SQLite database (`bukhari.db`), loaded at startup.
2. **UI** — Browse by book (பாகம்), view hadith list, read full hadith text, and search.
3. **TTS** — When the user taps play, the Tamil text is:
   - **Tokenized** character-by-character using the MMS-TTS-TAM vocabulary
   - **Chunked** into sentence-sized pieces (≤ 800 tokens each) to avoid blocking the UI
   - **Synthesized** on-device by the VITS model running through MNN (C++ via FFI)
   - **Played back** as 16 kHz mono PCM audio

## Native Build (MNN)

The native TTS wrapper is built automatically by the Flutter/Gradle CMake integration. MNN is compiled from source under `3rd_party/MNN/` with these options:

- CPU-only (no OpenCL/Vulkan)
- ARM FP16 enabled (`MNN_ARM82`)
- Shared library (`libmnn_tts.so`)

No manual native build step is needed — `flutter run` handles everything.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| CMake not found | Install CMake ≥ 3.22.1 via Android Studio SDK Manager |
| NDK not found | Set `ANDROID_NDK_HOME` or install NDK via SDK Manager |
| Model asset missing | Run `cp model_fp16_int8.mnn tamil_hadith_app/assets/models/` |
| ANR on long hadiths | Already handled — text is chunked before synthesis |
