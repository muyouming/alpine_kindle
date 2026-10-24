#!/bin/sh
# Copy the Kindle-provided binaries needed by bridge mode into assets/.
# These are not redistributed in this repo.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ASSETS="$HERE/assets"
KINDLE="${KINDLE:-root@192.168.3.179}"
PORT="${PORT:-2022}"

mkdir -p "$ASSETS"

echo "Fetching fbink from $KINDLE ..."
if ! scp -P "$PORT" "$KINDLE:/mnt/us/libkh/bin/fbink" "$ASSETS/fbink.bin"; then
    echo "trying KMC path ..."
    scp -P "$PORT" "$KINDLE:/var/local/kmc/kindlehf/bin/fbink" "$ASSETS/fbink.bin"
fi

echo "Fetching Kindle glibc loader/libs ..."
scp -P "$PORT" \
    "$KINDLE:/lib/ld-linux-armhf.so.3" \
    "$KINDLE:/lib/libc.so.6" \
    "$KINDLE:/lib/libm.so.6" \
    "$ASSETS/"

chmod +x "$ASSETS/fbink.bin"
echo "assets ready:"
ls -lh "$ASSETS"
