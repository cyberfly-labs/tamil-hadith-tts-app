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
#include <unistd.h>   // sysconf
#endif

// NEON intrinsics for ARM post-processing (aarch64 always has NEON)
#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__)
#include <arm_neon.h>
#define HAS_NEON 1
#else
#define HAS_NEON 0
#endif

using namespace MNN::Express;

// Ensure global executor config runs exactly once (even with multiple engines)
static std::once_flag g_executor_once;

// ─── Bucketing: reduce dynamic shape overhead ───
// VITS recompiles part of its graph when input shape changes.
// By snapping to fixed bucket sizes, we get graph-cache hits on repeat lengths.
// Buckets chosen to cover Dart-side _maxTokensPerChunk = 320 with padding ≤2×.
static const int kBuckets[] = {32, 64, 128, 192, 256, 320, 384};
static const int kNumBuckets = sizeof(kBuckets) / sizeof(kBuckets[0]);
static const int kMaxBucket  = kBuckets[kNumBuckets - 1];

static int _snapToBucket(int seq_len) {
    for (int i = 0; i < kNumBuckets; i++) {
        if (seq_len <= kBuckets[i]) return kBuckets[i];
    }
    // Exceeds largest bucket — round up to next multiple of 64
    return ((seq_len + 63) / 64) * 64;
}

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

// ─── Auto-detect optimal thread count for INT8 workloads on Android ───
// INT8 ops are memory-bound; too many threads cause cache contention.
static int _autoThreadCount() {
#ifdef __ANDROID__
    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    if (cores >= 8) return 4;  // Flagship (4 big + 4 little)
    if (cores >= 6) return 3;  // Mid-range (2 big + 4 little)
    if (cores >= 4) return 2;  // Budget
    return 1;
#else
    return 4;  // Desktop / iOS
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

    // ── Ping-pong double buffer ──
    // Two output buffers: previous call's data stays valid until the call
    // *after* the next one, giving callers a full inference window to copy.
    std::vector<float> audio_buffers[2];
    int active_buffer;  // 0 or 1 — alternates each synthesize call

    // Reusable input VARP vector (always 5 elements, no heap alloc per call)
    std::vector<VARP> input_vars;

    // Frozen scalar VARPs — created once at init.
    // Single-speaker app: noise/length scales never change at runtime.
    VARP frozen_ns, frozen_ls, frozen_nsw;

    // ── Reusable token input VARPs (replaces _Const per call) ──
    // Pre-allocated _Input tensors per bucket size.
    VARP x_input;        // Reusable token tensor
    VARP x_len_input;    // Reusable length scalar
    int  current_bucket; // Currently allocated bucket size (0 = none)

    // ── Cached writeMap pointers ──
    // writeMap<int>() syncs with the backend and may flush caches.
    // In static graph mode (_Input memory is stable), we cache the pointer
    // at bucket creation time and write directly — zero overhead per call.
    int* x_ptr_cached;       // Points into x_input's tensor buffer
    int* x_len_ptr_cached;   // Points into x_len_input's tensor buffer

    // ── Smart zeroing state ──
    // Tracks previous seq_len so we only memset the stale tail rather
    // than zeroing the entire padding region every call.
    int prev_seq_len;
};

// ─── Ensure x_input matches the required bucket size ───
// When the bucket changes, we create a new _Input and cache its writeMap
// pointer. The buffer is pre-zeroed so subsequent calls only need to
// memcpy tokens + zero the stale tail (if any).
static void _ensureBucket(MNN_TTS_Engine* engine, int bucket) {
    if (engine->current_bucket == bucket) return;
    // Create new _Input with the bucket shape — MNN caches the compiled graph
    engine->x_input = _Input({1, bucket}, NCHW, halide_type_of<int>());
    engine->current_bucket = bucket;
    // Cache pointer and pre-zero the entire buffer once
    engine->x_ptr_cached = engine->x_input->writeMap<int>();
    std::memset(engine->x_ptr_cached, 0, bucket * sizeof(int));
    engine->prev_seq_len = 0;
}

extern "C" {

MNN_TTS_Engine* tts_create_engine(const char* model_path, int thread_count) {
    if (!model_path) return nullptr;

    auto engine = new (std::nothrow) MNN_TTS_Engine();
    if (!engine) return nullptr;

    engine->model_path = model_path;
    engine->thread_count = (thread_count > 0) ? thread_count : _autoThreadCount();
    engine->current_bucket = 0;
    engine->x_ptr_cached = nullptr;
    engine->x_len_ptr_cached = nullptr;
    engine->prev_seq_len = 0;
    engine->active_buffer = 0;

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
    float ns_init = 0.667f, ls_init = 1.15f, nsw_init = 0.8f;
    engine->frozen_ns  = _Const(&ns_init,  {1}, NCHW, halide_type_of<float>());
    engine->frozen_ls  = _Const(&ls_init,  {1}, NCHW, halide_type_of<float>());
    engine->frozen_nsw = _Const(&nsw_init, {1}, NCHW, halide_type_of<float>());

    // Pre-allocate reusable x_len _Input (shape never changes: always {1})
    engine->x_len_input = _Input({1}, NCHW, halide_type_of<int>());
    engine->x_len_ptr_cached = engine->x_len_input->writeMap<int>();
    engine->x_len_ptr_cached[0] = 0;

    // Pre-allocate input VARP vector (always 5 elements)
    engine->input_vars.resize(5);

    // ── Pre-warm inference with the most common bucket sizes ──
    // First MNN inference per shape is slow due to graph compilation.
    // Warm up the 2 most common buckets so real calls hit cached graphs.
    try {
        const int warmup_buckets[] = {64, 192};
        for (int bucket : warmup_buckets) {
            _ensureBucket(engine, bucket);

            // Fill minimal tokens via cached pointer (pre-zeroed by _ensureBucket)
            engine->x_ptr_cached[0] = 1; engine->x_ptr_cached[2] = 2;

            engine->x_len_ptr_cached[0] = 3;

            engine->input_vars[0] = engine->x_input;
            engine->input_vars[1] = engine->x_len_input;
            engine->input_vars[2] = engine->frozen_ns;
            engine->input_vars[3] = engine->frozen_ls;
            engine->input_vars[4] = engine->frozen_nsw;

            auto warmup_out = engine->module->onForward(engine->input_vars);
            if (!warmup_out.empty() && warmup_out[0].get() != nullptr) {
                warmup_out[0]->readMap<float>();
            }
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
    const int32_t* input_ids,
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

        // ── Bucketed input: snap to fixed size ──
        // Graph recompilation only happens when bucket size changes.
        int bucket = _snapToBucket(seq_len);
        _ensureBucket(engine, bucket);

        // ── Fill token data via cached pointer (zero-alloc, zero-sync) ──
        // x_ptr_cached is stable in static graph mode: no writeMap() call.
        std::memcpy(engine->x_ptr_cached, input_ids, seq_len * sizeof(int));

        // Smart zeroing: only clear the stale tail from the *previous* call
        // rather than the entire (bucket - seq_len) padding region.
        // The buffer was pre-zeroed at bucket creation, so we only need to
        // wipe [seq_len..prev_seq_len) when the new data is shorter.
        if (seq_len < engine->prev_seq_len) {
            std::memset(engine->x_ptr_cached + seq_len, 0,
                        (engine->prev_seq_len - seq_len) * sizeof(int));
        }
        engine->prev_seq_len = seq_len;

        // Write actual length via cached pointer — single int store
        engine->x_len_ptr_cached[0] = seq_len;

        // Use frozen VARPs when params match defaults (common path);
        // otherwise create fresh scalar VARPs (cheap, ~µs).
        VARP ns_var  = (noise_scale   == 0.667f) ? engine->frozen_ns
                     : _Const(&noise_scale,   {1}, NCHW, halide_type_of<float>());
        VARP ls_var  = (length_scale  == 1.15f)  ? engine->frozen_ls
                     : _Const(&length_scale,  {1}, NCHW, halide_type_of<float>());
        VARP nsw_var = (noise_scale_w == 0.8f)   ? engine->frozen_nsw
                     : _Const(&noise_scale_w, {1}, NCHW, halide_type_of<float>());

        engine->input_vars[0] = engine->x_input;
        engine->input_vars[1] = engine->x_len_input;
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

        // ── Copy + peak-detect in one pass (into ping-pong buffer) ──
        const int buf_idx = engine->active_buffer;
        engine->audio_buffers[buf_idx].resize(total_elements);
        float* __restrict__ dst = engine->audio_buffers[buf_idx].data();
        float peak = 0.0f;

#if HAS_NEON
        // NEON: process 4 floats per iteration with vector abs + max
        {
            float32x4_t v_peak = vdupq_n_f32(0.0f);
            size_t i = 0;
            const size_t neon4 = total_elements & ~size_t(3);
            for (; i < neon4; i += 4) {
                float32x4_t v = vld1q_f32(src + i);
                vst1q_f32(dst + i, v);
                v_peak = vmaxq_f32(v_peak, vabsq_f32(v));
            }
            // Horizontal max of the 4 lanes
            float32x2_t v2 = vpmax_f32(vget_low_f32(v_peak), vget_high_f32(v_peak));
            v2 = vpmax_f32(v2, v2);
            peak = vget_lane_f32(v2, 0);
            // Scalar tail
            for (; i < total_elements; i++) {
                dst[i] = src[i];
                float a = std::fabs(src[i]);
                if (a > peak) peak = a;
            }
        }
#else
        // Scalar fallback — unrolled copy+peak for better pipelining
        {
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
#endif

        // ── Peak-normalize: boost audio to target level ──
        constexpr float target_peak = 0.92f;
        constexpr float min_peak    = 0.01f;
        if (peak > min_peak && peak < target_peak) {
            const float gain = target_peak / peak;
#if HAS_NEON
            {
                float32x4_t v_gain = vdupq_n_f32(gain);
                size_t i = 0;
                const size_t neon4 = total_elements & ~size_t(3);
                for (; i < neon4; i += 4) {
                    float32x4_t v = vld1q_f32(dst + i);
                    vst1q_f32(dst + i, vmulq_f32(v, v_gain));
                }
                for (; i < total_elements; i++) {
                    dst[i] *= gain;
                }
            }
#else
            for (size_t i = 0; i < total_elements; i++) {
                dst[i] *= gain;
            }
#endif
        }

        *output_data = engine->audio_buffers[buf_idx].data();
        *output_len  = total_elements;

        // Swap to the other buffer for the next call — caller's pointer
        // remains valid until the call *after* next.
        engine->active_buffer ^= 1;

        return TTS_SUCCESS;
    } catch (const std::exception& e) {
        engine->last_error = std::string("Exception during inference: ") + e.what();
        return TTS_ERROR_INFERENCE;
    } catch (...) {
        engine->last_error = "Unknown exception during inference";
        return TTS_ERROR_INFERENCE;
    }
}

// No-op: output uses ping-pong double buffer — each call's pointer stays
// valid until the call *after* the next synthesize. Callers should still
// copy data promptly. Kept for ABI compatibility.
void tts_free_output(float* /* output_data */) {
    // Intentionally empty. Do NOT free() — pointer is engine->audio_buffers[].data().
}

const char* tts_get_last_error(MNN_TTS_Engine* engine) {
    if (!engine) return "Null engine";
    return engine->last_error.c_str();
}

} // extern "C"
