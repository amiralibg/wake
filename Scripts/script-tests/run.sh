#!/bin/sh
# Builds and runs the shared page-script tests in a real WKWebView.
set -e
cd "$(dirname "$0")/../.."
out=build/script-tests
mkdir -p "$out"
rm -rf "$out/scripts" && cp -R shared/scripts "$out/scripts"
swiftc -swift-version 5 -O Wake/Support/SharedScript.swift Scripts/script-tests/main.swift -o "$out/run"
"$out/run"
