#!/bin/sh
# Inside the container: a virtual display, a session bus, and Wake on it.
# Test data lives in /tmp/wakedata (fresh each container).
rm -f /tmp/.X99-lock; Xvfb :99 -screen 0 1600x1000x24 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 1
eval "$(dbus-launch --sh-syntax)"
export WAKE_DATA_DIR=${WAKE_DATA_DIR:-/tmp/wakedata}
# No GPU and no user namespaces in the container.
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
[ -n "$WAKE_GPU" ] || export WAKE_NO_GPU=1
exec /wake-target/debug/wake "$@"
