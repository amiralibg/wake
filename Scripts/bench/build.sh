#!/bin/zsh
# Builds the benchmark variant of Wake: Release optimisation, the BENCH scenario
# driver compiled in, and its own bundle id (so its data never mixes with yours).
#
#   Scripts/bench/build.sh [variant]   (default "Bench"; e.g. "BenchBase" for a frozen baseline)
set -euo pipefail
cd "${0:A:h}/../.."
variant=${1:-Bench}
# BENCH_SOURCE builds another checkout (e.g. a frozen copy of the code before a fix).
out="$PWD/build/$variant"
[[ -n ${BENCH_SOURCE:-} ]] && cd "$BENCH_SOURCE"
xcodegen generate >/dev/null
xcodebuild -project Wake.xcodeproj -scheme Wake -configuration Release \
  -derivedDataPath "$out" \
  PRODUCT_BUNDLE_IDENTIFIER=app.wake.Wake.bench \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='BENCH' \
  build 2>&1 | grep -E "error:|warning:|BUILD" | grep -v appintents || true
clang -O2 -o "$out/responsible" Scripts/bench/responsible.c
