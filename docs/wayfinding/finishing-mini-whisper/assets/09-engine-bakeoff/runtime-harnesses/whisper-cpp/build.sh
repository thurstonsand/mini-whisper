#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
source_root="$root/.artifacts/whisper.cpp"
build_root="$source_root/build"
revision=f049fff95a089aa9969deb009cdd4892b3e74916

test "$(git -C "$source_root" rev-parse HEAD)" = "$revision"

cmake -S "$source_root" -B "$build_root" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON
cmake --build "$build_root" --target whisper-cli parakeet-cli -j 8

c++ -std=c++17 -O3 -arch arm64 \
  -I "$source_root/include" \
  -I "$source_root/ggml/include" \
  -I "$source_root/examples" \
  "$root/runtime-harnesses/whisper-cpp/main.cpp" \
  "$build_root/examples/libcommon.a" \
  "$build_root/bin/libparakeet.dylib" \
  "$build_root/bin/libwhisper.dylib" \
  "$build_root/bin/libggml.dylib" \
  "$build_root/bin/libggml-cpu.dylib" \
  "$build_root/bin/libggml-blas.dylib" \
  "$build_root/bin/libggml-metal.dylib" \
  "$build_root/bin/libggml-base.dylib" \
  -Wl,-rpath,"$build_root/bin" \
  -o "$root/.artifacts/whisper-cpp-harness"
