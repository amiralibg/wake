#!/bin/sh
# Builds and runs the content-blocker tests (downloads EasyList and EasyPrivacy).
set -e
cd "$(dirname "$0")/../.."
out=build/blocker-test
mkdir -p "$out"
swiftc -swift-version 5 -O Wake/Features/Blocker/FilterListConverter.swift Scripts/blocker-test/main.swift -o "$out/run"
"$out/run"
