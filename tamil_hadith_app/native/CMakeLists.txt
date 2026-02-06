cmake_minimum_required(VERSION 3.10)
project(mnn_tts_native)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# MNN 3.3.0 source directory
if(DEFINED ENV{MNN_DIR})
    set(MNN_DIR $ENV{MNN_DIR})
else()
    set(MNN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../3rd_party/MNN")
endif()

# MNN build options — minimal build for inference only.
# These are CACHE variables so they are written once and then
# respected on subsequent builds WITHOUT forcing a re-configure,
# which was the root cause of MNN recompiling every time.
set(MNN_BUILD_SHARED_LIBS ON CACHE BOOL "Build MNN as shared lib")
set(MNN_BUILD_TOOLS OFF CACHE BOOL "")
set(MNN_BUILD_QUANTOOLS OFF CACHE BOOL "")
set(MNN_BUILD_CONVERTER OFF CACHE BOOL "")
set(MNN_BUILD_BENCHMARK OFF CACHE BOOL "")
set(MNN_BUILD_TEST OFF CACHE BOOL "")
set(MNN_BUILD_DEMO OFF CACHE BOOL "")
set(MNN_BUILD_TRAIN OFF CACHE BOOL "")
set(MNN_SEP_BUILD OFF CACHE BOOL "")
set(MNN_PORTABLE_BUILD ON CACHE BOOL "")
set(MNN_USE_THREAD_POOL ON CACHE BOOL "")

if(ANDROID)
    set(MNN_OPENCL OFF CACHE BOOL "")
    set(MNN_VULKAN OFF CACHE BOOL "")
    set(MNN_ARM82 ON CACHE BOOL "")
endif()

# Build MNN from source
add_subdirectory(${MNN_DIR} ${CMAKE_BINARY_DIR}/MNN)

# Include MNN headers
include_directories(${MNN_DIR}/include)

# ── Aggressive compile flags for real-time TTS ──
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -ffast-math -funsafe-math-optimizations -flto")
    set(CMAKE_C_FLAGS_RELEASE   "${CMAKE_C_FLAGS_RELEASE}   -O3 -ffast-math -funsafe-math-optimizations -flto")
endif()

if(ANDROID)
    # NEON is auto-enabled on aarch64, but explicit for armv7
    if(CMAKE_ANDROID_ARCH_ABI STREQUAL "armeabi-v7a")
        add_compile_options(-mfpu=neon)
    endif()
    # LTO for all builds on Android
    add_compile_options(-flto)
    add_link_options(-flto)
endif()

# Build our TTS wrapper as a shared library
add_library(mnn_tts SHARED src/mnn_tts.cpp)

# Link against MNN
target_link_libraries(mnn_tts MNN)

if(ANDROID)
    target_link_libraries(mnn_tts log)
endif()

target_include_directories(mnn_tts PUBLIC src)
