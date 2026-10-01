#!/bin/sh
# Runs a command in the Linux dev container with the repo at /wake and cargo's
# caches in named volumes (so rebuilds are incremental).
#   desktop/docker/run.sh cargo build --manifest-path desktop/host/Cargo.toml
# With WAKE_X=1 it starts a virtual display (Xvfb :99, 1600x1000) first.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
exec docker run --rm ${WAKE_DOCKER_ARGS:-} \
  -v "$ROOT":/wake \
  -v wake-cargo-registry:/usr/local/cargo/registry \
  -v wake-cargo-git:/usr/local/cargo/git \
  -v wake-target:/wake-target \
  -e CARGO_TARGET_DIR=/wake-target \
  -w /wake wake-linux-dev sh -c "$*"
