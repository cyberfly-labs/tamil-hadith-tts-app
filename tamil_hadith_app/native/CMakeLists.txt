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

# MNN build options — minimal build for inference only
set(MNN_BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
set(MNN_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_QUANTOOLS OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_CONVERTER OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_BENCHMARK OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_TEST OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_DEMO OFF CACHE BOOL "" FORCE)
set(MNN_BUILD_TRAIN OFF CACHE BOOL "" FORCE)
set(MNN_SEP_BUILD OFF CACHE BOOL "" FORCE)
set(MNN_PORTABLE_BUILD ON CACHE BOOL "" FORCE)
set(MNN_USE_THREAD_POOL ON CACHE BOOL "" FORCE)

if(ANDROID)
    set(MNN_OPENCL OFF CACHE BOOL "" FORCE)
    set(MNN_VULKAN OFF CACHE BOOL "" FORCE)
    set(MNN_ARM82 ON CACHE BOOL "" FORCE)
endif()

# Build MNN from source
add_subdirectory(${MNN_DIR} ${CMAKE_BINARY_DIR}/MNN)

# Include MNN headers
include_directories(${MNN_DIR}/include)

# Build our TTS wrapper as a shared library
add_library(mnn_tts SHARED src/mnn_tts.cpp)

# Link against MNN
target_link_libraries(mnn_tts MNN)

if(ANDROID)
    target_link_libraries(mnn_tts log)
endif()

target_include_directories(mnn_tts PUBLIC src)
