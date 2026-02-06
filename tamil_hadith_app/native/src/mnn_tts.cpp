#include "mnn_tts.h"

// MNN Module API headers (required for dynamic-shape VITS model)
#include <MNN/expr/Expr.hpp>
#include <MNN/expr/Module.hpp>
#include <MNN/expr/Executor.hpp>
#include <MNN/expr/NeuralNetWorkOp.hpp>
#include <MNN/expr/MathOp.hpp>
#include <MNN/MNNForwardType.h>

#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

using namespace MNN::Express;

// Global mutex to serialize MNN inference calls
static std::mutex g_tts_inference_mutex;

struct MNN_TTS_Engine {
    std::unique_ptr<Module> module;
    std::string model_path;
    std::string last_error;
    int thread_count;
};

extern "C" {

MNN_TTS_Engine* tts_create_engine(const char* model_path, int thread_count) {
    if (!model_path) return nullptr;

    auto engine = new (std::nothrow) MNN_TTS_Engine();
    if (!engine) return nullptr;

    engine->model_path = model_path;
    engine->thread_count = (thread_count > 0) ? thread_count : 4;

    // Configure backend
    Module::BackendInfo backend;
    backend.type = MNN_FORWARD_CPU;
    MNN::BackendConfig backendConfig;
    // Use Normal precision — the fp16_int8 model already encodes its own
    // quantisation; forcing Precision_Low on top degrades audio quality.
    backendConfig.precision = MNN::BackendConfig::Precision_Normal;
    backendConfig.memory = MNN::BackendConfig::Memory_Low;
    backend.config = &backendConfig;

    // Set thread count globally for the CPU executor
    MNN::Express::Executor::getGlobalExecutor()->setGlobalExecutorConfig(
        MNN_FORWARD_CPU, backendConfig, engine->thread_count);

    Module::Config config;
    config.shapeMutable = true;  // VITS has dynamic sequence length
    config.dynamic = false;      // Static graph mode for speed
    config.backend = &backend;

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

    std::lock_guard<std::mutex> lock(g_tts_inference_mutex);

    try {
        int seq_len = (int)input_len;

        // Build int32 token array (MNN MMS-TTS uses int32, not int64)
        std::vector<int> tokens_i32(seq_len);
        for (int i = 0; i < seq_len; i++) {
            tokens_i32[i] = (int)input_ids[i];
        }

        // Create input VARPs
        // x: [1, seq_len] int32
        VARP x = _Const(tokens_i32.data(), {1, seq_len}, NCHW, halide_type_of<int>());
        // x_length: [1] int32
        int len_val = seq_len;
        VARP x_len = _Const(&len_val, {1}, NCHW, halide_type_of<int>());
        // noise_scale: [1] float
        VARP ns = _Const(&noise_scale, {1}, NCHW, halide_type_of<float>());
        // length_scale: [1] float
        VARP ls = _Const(&length_scale, {1}, NCHW, halide_type_of<float>());
        // noise_scale_w: [1] float
        VARP nsw = _Const(&noise_scale_w, {1}, NCHW, halide_type_of<float>());

        // Run inference
        std::vector<VARP> inputs = {x, x_len, ns, ls, nsw};
        std::vector<VARP> outputs = engine->module->onForward(inputs);

        if (outputs.empty() || outputs[0] == nullptr) {
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

        float* result = (float*)malloc(total_elements * sizeof(float));
        if (!result) {
            engine->last_error = "Out of memory allocating output buffer";
            return TTS_ERROR_OUT_OF_MEMORY;
        }

        memcpy(result, src, total_elements * sizeof(float));

        *output_data = result;
        *output_len = total_elements;

        return TTS_SUCCESS;
    } catch (const std::exception& e) {
        engine->last_error = std::string("Exception during inference: ") + e.what();
        return TTS_ERROR_INFERENCE;
    } catch (...) {
        engine->last_error = "Unknown exception during inference";
        return TTS_ERROR_INFERENCE;
    }
}

void tts_free_output(float* output_data) {
    if (output_data) {
        free(output_data);
    }
}

const char* tts_get_last_error(MNN_TTS_Engine* engine) {
    if (!engine) return "Null engine";
    return engine->last_error.c_str();
}

} // extern "C"
