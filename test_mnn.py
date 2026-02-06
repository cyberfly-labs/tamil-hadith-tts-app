#!/usr/bin/env python3
"""Test MNN model inference with the existing model_int8.mnn"""
import MNN
import MNN.expr as F
import MNN.numpy as np

path = '/Users/abu/tamil-hadith-audio/model_int8.mnn'

# Use Module API for dynamic shape models
inputs = ['x', 'x_length', 'noise_scale', 'length_scale', 'noise_scale_w']
outputs = ['y']

module = MNN.nn.load_module_from_file(path, inputs, outputs)
print('Module loaded successfully')

# Test tokens: blank-interleaved for "அந்" (அ=1, ந=5, ்=18)
# With add_blank: [0, 1, 0, 5, 0, 18, 0]
test_tokens = [0, 1, 0, 5, 0, 18, 0]
seq_len = len(test_tokens)

x = F.const(test_tokens, [1, seq_len], F.NCHW, F.int)
x_length = F.const([seq_len], [1], F.NCHW, F.int)
noise_scale = F.const([0.667], [1], F.NCHW, F.float)
length_scale = F.const([1.0], [1], F.NCHW, F.float)
noise_scale_w = F.const([0.8], [1], F.NCHW, F.float)

print(f'Running inference with {seq_len} tokens...')
result = module.forward([x, x_length, noise_scale, length_scale, noise_scale_w])
y = result[0] if isinstance(result, list) else result
print(f'Output shape: {y.shape}')
print(f'Output dtype: {y.dtype}')
audio = np.array(y)
print(f'Audio samples: {audio.shape}, min={audio.min():.4f}, max={audio.max():.4f}')
print(f'Duration: {audio.size / 16000:.2f}s at 16kHz')
print('SUCCESS - Model works!')
