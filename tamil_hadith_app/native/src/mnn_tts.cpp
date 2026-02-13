#include "mnn_tts.h"

// MNN Module API headers (required for dynamic-shape VITS model)
#include <MNN/expr/Expr.hpp>
#include <MNN/expr/Module.hpp>
#include <MNN/expr/Executor.hpp>
#include <MNN/expr/NeuralNetWorkOp.hpp>
#include <MNN/expr/MathOp.hpp>
#include <MNN/MNNForwardType.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#ifdef __ANDROID__
#include <sched.h>
#endif

using namespace MNN::Express;

// Ensure global executor config runs exactly once (even with multiple engines)
static std::once_flag g_executor_once;

// Pin current thread to big/performance cores on Android.
// Typical ARM big.LITTLE: cores 4-7 are big on most SoCs.
static void _pinToBigCores() {
#ifdef __ANDROID__
    cpu_set_t set;
    CPU_ZERO(&set);
    // Try cores 4-7 (big cores on most Snapdragon/Dimensity/Exynos)
    for (int i = 4; i < 8; i++) {
        CPU_SET(i, &set);
    }
    sched_setaffinity(0, sizeof(set), &set);
#endif
}

// ─── Engine struct with per-instance state for zero-alloc inference ───

struct MNN_TTS_Engine {
    std::unique_ptr<Module> module;
    std::string model_path;
    std::string last_error;
    int thread_count;

    // Per-engine mutex (no global bottleneck — allows parallel engines)
    std::mutex lock;

    // Reusable output buffer (avoids malloc/free every inference call)
    std::vector<float> audio_buffer;

    // Reusable token buffer (avoids heap alloc per inference)
    std::vector<int> token_buffer;

    // Reusable input VARP vector (avoids heap alloc per inference)
    std::vector<VARP> input_vars;

    // Frozen scalar VARPs — created once at init.
    // Single-speaker app: noise/length scales never change at runtime.
    VARP frozen_ns, frozen_ls, frozen_nsw;
};

extern "C" {

MNN_TTS_Engine* tts_create_engine(const char* model_path, int thread_count) {
    if (!model_path) return nullptr;

    auto engine = new (std::nothrow) MNN_TTS_Engine();
    if (!engine) return nullptr;

    engine->model_path = model_path;
    engine->thread_count = (thread_count > 0) ? thread_count : 4;

    // Configure backend — prefer big cores for real-time speech
    Module::BackendInfo backend;
    backend.type = MNN_FORWARD_CPU;
    MNN::BackendConfig backendConfig;
    // Use Normal precision — the fp16_int8 model already encodes its own
    // quantisation; forcing Precision_Low on top degrades audio quality.
    backendConfig.precision = MNN::BackendConfig::Precision_Normal;
    backendConfig.memory    = MNN::BackendConfig::Memory_Low;
    backendConfig.power     = MNN::BackendConfig::Power_High;  // Pin to big cores
    backend.config = &backendConfig;

    // Set global executor config exactly once (prevents race & redundant setup)
    int tc = engine->thread_count;
    std::call_once(g_executor_once, [&backendConfig, tc]() {
        MNN::Express::Executor::getGlobalExecutor()->setGlobalExecutorConfig(
            MNN_FORWARD_CPU, backendConfig, tc);
        _pinToBigCores();
    });

    Module::Config config;
    config.shapeMutable = true;   // VITS has dynamic sequence length
    config.dynamic      = false;  // Static graph mode for speed
    config.backend      = &backend;

    // VITS model input/output names (from facebook/mms-tts-tam ONNX export)
    std::vector<std::string> input_names = {
        "x", "x_length", "noise_scale", "length_scale", "noise_scale_w"
    };
    std::vector<std::string> output_names = {"y"};

    Module* mod = Module::load(
        input_names, output_names,
        model_path, &config
    );

    if (!mod) {
        engine->last_error = "Failed to load MNN module from: " + std::string(model_path);
        delete engine;
        return nullptr;
    }

    engine->module.reset(mod);

    // ── Default scalar VARPs (used when caller passes the standard values) ──
    // Creating _Const VARPs is cheap (~µs) but we cache the common case.
    float ns_init = 0.667f, ls_init = 1.15f, nsw_init = 0.8f;
    engine->frozen_ns  = _Const(&ns_init,  {1}, NCHW, halide_type_of<float>());
    engine->frozen_ls  = _Const(&ls_init,  {1}, NCHW, halide_type_of<float>());
    engine->frozen_nsw = _Const(&nsw_init, {1}, NCHW, halide_type_of<float>());

    // Pre-allocate input VARP vector (always 5 elements, no heap alloc per call)
    engine->input_vars.resize(5);

    // ── Pre-warm inference ──
    // First MNN inference is always slow due to shape compilation & kernel JIT.
    // Run a tiny 3-token dummy to pay that cost at init, not on the first real call.
    try {
        int dummy_tokens[] = {1, 0, 2};  // minimal with blank interleave
        int dummy_len = 3;

        VARP x     = _Const(dummy_tokens, {1, dummy_len}, NCHW, halide_type_of<int>());
        VARP x_len = _Const(&dummy_len, {1}, NCHW, halide_type_of<int>());

        engine->input_vars[0] = x;
        engine->input_vars[1] = x_len;
        engine->input_vars[2] = engine->frozen_ns;
        engine->input_vars[3] = engine->frozen_ls;
        engine->input_vars[4] = engine->frozen_nsw;

        auto warmup_out = engine->module->onForward(engine->input_vars);
        // Force readMap to complete the computation graph
        if (!warmup_out.empty() && warmup_out[0].get() != nullptr) {
            warmup_out[0]->readMap<float>();
        }
    } catch (...) {
        // Warmup failure is non-fatal — first real call will just be slower
    }

    return engine;
}

void tts_destroy_engine(MNN_TTS_Engine* engine) {
    if (engine) {
        engine->module.reset();
        delete engine;
    }
}

TTS_ErrorCode tts_synthesize(
    MNN_TTS_Engine* engine,
    const int64_t* input_ids,
    size_t input_len,
    float noise_scale,
    float length_scale,
    float noise_scale_w,
    float** output_data,
    size_t* output_len
) {
    if (!engine || !engine->module || !input_ids || !output_data || !output_len || input_len == 0) {
        return TTS_ERROR_INVALID_PARAM;
    }

    // Per-engine lock (not global — parallel engines won't block each other)
    std::lock_guard<std::mutex> lock(engine->lock);

    try {
        int seq_len = static_cast<int>(input_len);

        // Narrow int64→int32 into reusable buffer (no heap alloc after first call)
        engine->token_buffer.resize(seq_len);
        for (int i = 0; i < seq_len; i++) {
            engine->token_buffer[i] = static_cast<int>(input_ids[i]);
        }

        // ── Build input VARPs ──
        // Tokens & length change every call → always fresh
        VARP x = _Const(engine->token_buffer.data(), {1, seq_len}, NCHW, halide_type_of<int>());
        int len_val = seq_len;
        VARP x_len = _Const(&len_val, {1}, NCHW, halide_type_of<int>());

        // Use frozen VARPs when params match defaults (common path);
        // otherwise create fresh scalar VARPs (cheap, ~µs).
        VARP ns_var  = (noise_scale   == 0.667f) ? engine->frozen_ns
                     : _Const(&noise_scale,   {1}, NCHW, halide_type_of<float>());
        VARP ls_var  = (length_scale  == 1.15f)  ? engine->frozen_ls
                     : _Const(&length_scale,  {1}, NCHW, halide_type_of<float>());
        VARP nsw_var = (noise_scale_w == 0.8f)   ? engine->frozen_nsw
                     : _Const(&noise_scale_w, {1}, NCHW, halide_type_of<float>());

        engine->input_vars[0] = x;
        engine->input_vars[1] = x_len;
        engine->input_vars[2] = ns_var;
        engine->input_vars[3] = ls_var;
        engine->input_vars[4] = nsw_var;

        // Run inference — thread_local avoids heap alloc for output vector
        thread_local std::vector<VARP> outputs;
        outputs = engine->module->onForward(engine->input_vars);

        if (outputs.empty() || outputs[0].get() == nullptr) {
            engine->last_error = "Module forward returned empty output";
            return TTS_ERROR_INFERENCE;
        }

        // Get output: y has shape [1, 1, audio_len]
        VARP y = outputs[0];
        auto info = y->getInfo();
        if (!info) {
            engine->last_error = "Failed to get output tensor info";
            return TTS_ERROR_INFERENCE;
        }

        size_t total_elements = info->size;
        const float* src = y->readMap<float>();
        if (!src) {
            engine->last_error = "Failed to read output tensor data";
            return TTS_ERROR_INFERENCE;
        }

        // Copy into reusable engine buffer + find peak in one pass.
        // Fused loop avoids a second scan over the data.
        engine->audio_buffer.resize(total_elements);
        float peak = 0.0f;
        {
            float* __restrict__ dst = engine->audio_buffer.data();
            // Unrolled copy+peak for better pipelining on ARM/x86
            size_t i = 0;
            const size_t unroll4 = total_elements & ~size_t(3);
            for (; i < unroll4; i += 4) {
                float s0 = src[i],   s1 = src[i+1];
                float s2 = src[i+2], s3 = src[i+3];
                dst[i]   = s0; dst[i+1] = s1;
                dst[i+2] = s2; dst[i+3] = s3;
                float a0 = std::fabs(s0), a1 = std::fabs(s1);
                float a2 = std::fabs(s2), a3 = std::fabs(s3);
                float m01 = a0 > a1 ? a0 : a1;
                float m23 = a2 > a3 ? a2 : a3;
                float m   = m01 > m23 ? m01 : m23;
                if (m > peak) peak = m;
            }
            for (; i < total_elements; i++) {
                dst[i] = src[i];
                float a = std::fabs(src[i]);
                if (a > peak) peak = a;
            }
        }

        // ── Peak-normalize: boost audio to target level ──
        constexpr float target_peak = 0.92f;
        constexpr float min_peak    = 0.01f;
        if (peak > min_peak && peak < target_peak) {
            const float gain = target_peak / peak;
            float* __restrict__ dst = engine->audio_buffer.data();
            for (size_t i = 0; i < total_elements; i++) {
                dst[i] *= gain;
            }
        }

        *output_data = engine->audio_buffer.data();
        *output_len  = total_elements;

        return TTS_SUCCESS;
    } catch (const std::exception& e) {
        engine->last_error = std::string("Exception during inference: ") + e.what();
        return TTS_ERROR_INFERENCE;
    } catch (...) {
        engine->last_error = "Unknown exception during inference";
        return TTS_ERROR_INFERENCE;
    }
}

// No-op: output buffer is now engine-owned (reusable vector).
// Kept for ABI compatibility — callers must copy data before next synthesize call.
void tts_free_output(float* /* output_data */) {
    // Intentionally empty. Do NOT free() — pointer is engine->audio_buffer.data().
}

const char* tts_get_last_error(MNN_TTS_Engine* engine) {
    if (!engine) return "Null engine";
    return engine->last_error.c_str();
}

} // extern "C"
