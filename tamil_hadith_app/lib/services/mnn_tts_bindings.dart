import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// --- FFI Type definitions matching mnn_tts.h (VITS / mms-tts-tam) ---

/// Opaque pointer to the native TTS engine
// ignore: camel_case_types
typedef MNN_TTS_Engine = Void;

// Native function typedefs
typedef TtsCreateEngineNative = Pointer<MNN_TTS_Engine> Function(
    Pointer<Utf8> modelPath, Int32 threadCount);
typedef TtsCreateEngineDart = Pointer<MNN_TTS_Engine> Function(
    Pointer<Utf8> modelPath, int threadCount);

typedef TtsDestroyEngineNative = Void Function(Pointer<MNN_TTS_Engine> engine);
typedef TtsDestroyEngineDart = void Function(Pointer<MNN_TTS_Engine> engine);

// Updated: VITS model needs noise_scale, length_scale, noise_scale_w
typedef TtsSynthesizeNative = Int32 Function(
    Pointer<MNN_TTS_Engine> engine,
    Pointer<Int64> inputIds,
    IntPtr inputLen,
    Float noiseScale,
    Float lengthScale,
    Float noiseScaleW,
    Pointer<Pointer<Float>> outputData,
    Pointer<IntPtr> outputLen);
typedef TtsSynthesizeDart = int Function(
    Pointer<MNN_TTS_Engine> engine,
    Pointer<Int64> inputIds,
    int inputLen,
    double noiseScale,
    double lengthScale,
    double noiseScaleW,
    Pointer<Pointer<Float>> outputData,
    Pointer<IntPtr> outputLen);

typedef TtsFreeOutputNative = Void Function(Pointer<Float> outputData);
typedef TtsFreeOutputDart = void Function(Pointer<Float> outputData);

typedef TtsGetLastErrorNative = Pointer<Utf8> Function(
    Pointer<MNN_TTS_Engine> engine);
typedef TtsGetLastErrorDart = Pointer<Utf8> Function(
    Pointer<MNN_TTS_Engine> engine);

/// FFI bindings to the native MNN TTS library (VITS / mms-tts-tam)
class MnnTtsBindings {
  late final DynamicLibrary _lib;
  late final TtsCreateEngineDart createEngine;
  late final TtsDestroyEngineDart destroyEngine;
  late final TtsSynthesizeDart synthesize;
  late final TtsFreeOutputDart freeOutput;
  late final TtsGetLastErrorDart getLastError;

  MnnTtsBindings() {
    _lib = _loadLibrary();
    createEngine = _lib
        .lookupFunction<TtsCreateEngineNative, TtsCreateEngineDart>(
            'tts_create_engine');
    destroyEngine = _lib
        .lookupFunction<TtsDestroyEngineNative, TtsDestroyEngineDart>(
            'tts_destroy_engine');
    synthesize = _lib
        .lookupFunction<TtsSynthesizeNative, TtsSynthesizeDart>(
            'tts_synthesize');
    freeOutput = _lib
        .lookupFunction<TtsFreeOutputNative, TtsFreeOutputDart>(
            'tts_free_output');
    getLastError = _lib
        .lookupFunction<TtsGetLastErrorNative, TtsGetLastErrorDart>(
            'tts_get_last_error');
  }

  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libmnn_tts.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libmnn_tts.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('mnn_tts.dll');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
