#!/bin/sh
# Rebuilds the host and restarts Wake in the `wake-test` container (keeps it
# running for docker exec: xdotool, screenshots). Extra args go to `wake`.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
"$ROOT/desktop/docker/run.sh" "cargo build --manifest-path desktop/host/Cargo.toml 2>&1 | grep -E '^(error|warning)' -A8 | head -60"
docker rm -f wake-test >/dev/null 2>&1 || true
docker run -d --name wake-test -e WAKE_DEBUG=1 \
  -v "$ROOT":/wake -v wake-cargo-registry:/usr/local/cargo/registry -v wake-target:/wake-target \
  -w /wake wake-linux-dev sh -c "${WAKE_FIXTURE:+desktop/docker/firefox-fixture.sh; }desktop/docker/app.sh $* > /tmp/wake.log 2>&1" >/dev/null
