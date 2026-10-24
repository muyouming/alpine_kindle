#!/bin/sh
# $1 = host X depth, $2 = host X geometry (WxH)
HOSTDEPTH="${1:-8}"
HOSTSIZE="${2:-1860x2480}"
chmod a+w /dev/shm # Otherwise the alpine user cannot use this (needed for chromium)
mkdir -p /tmp/runtime-alpine
chmod 700 /tmp/runtime-alpine
chown alpine:alpine /tmp/runtime-alpine

if [ "$HOSTDEPTH" = "24" ] || [ "$HOSTDEPTH" = "32" ]; then
    echo "startgui: Xephyr mode ${HOSTSIZE}x24"
    env DISPLAY=:0 Xephyr :1 -title "L:D_N:application_ID:xephyr" -ac -br \
        -screen ${HOSTSIZE}x24 -cc 4 -reset -terminate & sleep 3
    su alpine -c "export DISPLAY=:1 XDG_RUNTIME_DIR=/tmp/runtime-alpine ICEAUTHORITY=/tmp/runtime-alpine/ICEauthority; dbus-run-session -- mate-session"
    killall Xephyr
else
    # Bridge mode: Kindle X is 8-bit, Chromium needs a 24-bit visual.
    echo "startgui: bridge mode ${HOSTSIZE}x24 (host depth $HOSTDEPTH)"
    Xvfb :1 -screen 0 ${HOSTSIZE}x24 -ac -nolisten tcp >/tmp/xvfb.log 2>&1 &
    XVFBPID=$!
    sleep 2
    su alpine -c "export DISPLAY=:1 XDG_RUNTIME_DIR=/tmp/runtime-alpine ICEAUTHORITY=/tmp/runtime-alpine/ICEauthority; dbus-run-session -- mate-session" >/tmp/mate.log 2>&1 &
    MATEPID=$!
    sleep 8
    python3 /usr/local/bin/bridge.py >/tmp/bridge.log 2>&1 &
    BRIDGEPID=$!
    python3 /usr/local/bin/touch.py >/tmp/touch.log 2>&1 &
    TOUCHPID=$!
    wait $MATEPID
    kill $BRIDGEPID $TOUCHPID $XVFBPID 2>/dev/null || true
    killall Xvfb 2>/dev/null || true
fi
