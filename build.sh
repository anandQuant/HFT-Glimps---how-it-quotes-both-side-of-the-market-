#!/bin/sh
# Linux / macOS: builds ./bin/mm_sim and ./bin/mm_tests   (needs cmake and a C++17 compiler)
set -e
cd "$(dirname "$0")"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
mkdir -p bin
cp build/mm_sim build/mm_tests bin/
echo
echo "Done. Try:  ./bin/mm_sim replay sample_data/sample_fake_nq.mbo.zst --from 14:00"
