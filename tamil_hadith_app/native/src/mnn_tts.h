#ifndef MNN_TTS_H
#define MNN_TTS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle for the TTS engine
typedef struct MNN_TTS_Engine MNN_TTS_Engine;

/// Error codes
typedef enum {
    TTS_SUCCESS = 0,
    TTS_ERROR_INVALID_PARAM = 1,
    TTS_ERROR_MODEL_LOAD = 2,
    TTS_ERROR_INFERENCE = 3,
    TTS_ERROR_OUT_OF_MEMORY = 4,
} TTS_ErrorCode;

/// Create a new TTS engine from a model file
/// @param model_path    Path to the .mnn model file
/// @param thread_count  Number of threads for inference (0 for auto)
/// @return Engine handle, or NULL on failure
MNN_TTS_Engine* tts_create_engine(const char* model_path, int thread_count);

/// Destroy the TTS engine and free resources
void tts_destroy_engine(MNN_TTS_Engine* engine);

/// Run VITS TTS inference (mms-tts-tam)
/// @param engine           The TTS engine handle
/// @param input_ids        Array of token IDs (with blanks already interleaved)
/// @param input_len        Length of input_ids array
/// @param noise_scale      Controls audio variation (default 0.667)
/// @param length_scale     Controls speaking rate (default 1.0)
/// @param noise_scale_w    Controls duration variation (default 0.8)
/// @param output_data      Pointer to receive output audio buffer (caller must free with tts_free_output)
/// @param output_len       Pointer to receive output audio length
/// @return Error code
TTS_ErrorCode tts_synthesize(
    MNN_TTS_Engine* engine,
    const int64_t* input_ids,
    size_t input_len,
    float noise_scale,
    float length_scale,
    float noise_scale_w,
    float** output_data,
    size_t* output_len
);

/// No-op (kept for ABI compatibility).
/// Output buffer is now engine-owned; callers must copy data before
/// the next tts_synthesize call on the same engine.
void tts_free_output(float* output_data);

/// Get the last error message
const char* tts_get_last_error(MNN_TTS_Engine* engine);

#ifdef __cplusplus
}
#endif

#endif // MNN_TTS_H
