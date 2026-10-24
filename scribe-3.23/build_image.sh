#!/bin/bash
# Build a fresh Alpine armv7 image for Kindle inside Docker.
# Runs as root in the builder container (binfmt qemu-arm already registered).
set -euo pipefail

REPO="${REPO:-https://dl-cdn.alpinelinux.org/alpine}"
BRANCH="${BRANCH:-v3.23}"
ARCH="${ARCH:-armv7}"
SIZE_MB="${SIZE_MB:-3584}"
BUILD="${BUILD:-/build}"
ROOT="$BUILD/rootfs"
IMAGE="$BUILD/alpine.ext3"
DL="$BUILD/dl"
APKSTATIC_DIR="$BUILD/apkstatic"

mkdir -p "$DL" "$APKSTATIC_DIR"

for f in fbink.bin ld-linux-armhf.so.3 libc.so.6 libm.so.6; do
    [ -f "$BUILD/assets/$f" ] || {
        echo "missing assets/$f -- run ./fetch_assets.sh with a Kindle connected" >&2
        exit 1
    }
done

echo "=== 1. apk-tools-static ($BRANCH/$ARCH) ==="
curl -fsSL "$REPO/$BRANCH/main/$ARCH/APKINDEX.tar.gz" -o "$DL/APKINDEX.tar.gz"
tar -xzOf "$DL/APKINDEX.tar.gz" APKINDEX > "$DL/APKINDEX"
APKVER="$(awk '/^P:apk-tools-static$/{f=1} f&&/^V:/{sub(/^V:/,"");print;exit}' "$DL/APKINDEX")"
[ -n "$APKVER" ] || { echo "apk-tools-static version not found"; exit 1; }
echo "apk-tools-static: $APKVER"
curl -fsSL "$REPO/$BRANCH/main/$ARCH/apk-tools-static-$APKVER.apk" -o "$DL/apk-tools-static.apk"
rm -rf "$APKSTATIC_DIR"
mkdir -p "$APKSTATIC_DIR"
tar -xzf "$DL/apk-tools-static.apk" -C "$APKSTATIC_DIR"
APKSTATIC="$APKSTATIC_DIR/sbin/apk.static"
chmod +x "$APKSTATIC"
"$APKSTATIC" --version

echo "=== 2. bootstrap rootfs ==="
if [ -d "$ROOT" ]; then
    for d in dev proc sys; do
        mountpoint -q "$ROOT/$d" && umount -R "$ROOT/$d" 2>/dev/null || true
    done
fi
rm -rf "$ROOT"
mkdir -p "$ROOT"
"$APKSTATIC" -X "$REPO/$BRANCH/main" -U --allow-untrusted --root "$ROOT" --initdb add alpine-base

mkdir -p "$ROOT/etc/apk"
printf '%s\n' "$REPO/$BRANCH/main" "$REPO/$BRANCH/community" > "$ROOT/etc/apk/repositories"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
cp /usr/bin/qemu-arm-static "$ROOT/usr/bin/qemu-arm-static"

echo "=== 3. bind mounts ==="
mkdir -p "$ROOT/proc" "$ROOT/sys" "$ROOT/dev" "$ROOT/dev/pts" "$ROOT/run/dbus"
mount -t proc proc "$ROOT/proc"
mount --rbind /dev "$ROOT/dev"
mount -t sysfs sysfs "$ROOT/sys"
trap 'umount "$ROOT/sys" 2>/dev/null || true; umount -R "$ROOT/dev" 2>/dev/null || true; umount "$ROOT/proc" 2>/dev/null || true' EXIT

echo "=== 4. install packages / configure (chroot) ==="
mkdir -p "$ROOT/tmp/assets"
cp "$BUILD"/assets/fbink.bin "$ROOT/tmp/assets/fbink.bin"
cp "$BUILD"/assets/ld-linux-armhf.so.3 "$BUILD"/assets/libc.so.6 "$BUILD"/assets/libm.so.6 "$ROOT/tmp/assets/"
cp "$BUILD"/assets/bridge.py "$BUILD"/assets/touch.py "$BUILD"/assets/startgui.sh "$ROOT/tmp/assets/"
cp "$BUILD/setup_chroot.sh" "$ROOT/tmp/setup_chroot.sh"
chmod +x "$ROOT/tmp/setup_chroot.sh"
chroot "$ROOT" /bin/sh /tmp/setup_chroot.sh

echo "=== 5. cleanup rootfs ==="
rm -f "$ROOT/tmp/setup_chroot.sh" "$ROOT/usr/bin/qemu-arm-static"
rm -rf "$ROOT/var/cache/apk"/* "$ROOT/tmp"/* "$ROOT/var/tmp"/* \
       "$ROOT/root/.cache" "$ROOT/home/alpine/.cache" "$ROOT/home/alpine/.git"
sync

echo "=== 6. unmount ==="
umount "$ROOT/sys"
umount -R "$ROOT/dev"
umount "$ROOT/proc"
trap - EXIT

echo "=== 7. create ext3 image (${SIZE_MB}MB) ==="
echo "rootfs size: $(du -sh "$ROOT" | cut -f1)"
rm -f "$IMAGE"
truncate -s "${SIZE_MB}M" "$IMAGE"
mke2fs -q -t ext3 -F -L alpine -d "$ROOT" "$IMAGE"
tune2fs -i 0 -c 0 "$IMAGE"
echo "--- filesystem ---"
dumpe2fs -h "$IMAGE" 2>/dev/null | grep -E 'Filesystem features|Block count|Block size|Filesystem state'
e2fsck -fn "$IMAGE" || true
echo "--- root listing ---"
debugfs -R 'ls -l /' "$IMAGE" 2>/dev/null
echo "=== done: $IMAGE ($(du -h "$IMAGE" | cut -f1)) ==="

echo "=== 8. create alpine.zip (deflate, no zip64) ==="
cd "$BUILD"
rm -f alpine.zip
zip -9 alpine.zip alpine.conf alpine.sh alpine.ext3
ls -lh alpine.zip alpine.ext3
