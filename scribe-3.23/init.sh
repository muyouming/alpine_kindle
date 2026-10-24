#!/bin/bash
set -e

# Docker Desktop's LinuxKit VM has no binfmt_misc registration for arm.
# Register qemu-arm inside this container's mount namespace so all ARM
# binaries (apk, post-install scripts, Chromium) execute transparently.
mkdir -p /proc/sys/fs/binfmt_misc
if ! grep -q ' /proc/sys/fs/binfmt_misc ' /proc/mounts; then
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]; then
    printf '%s\n' ':qemu-arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-arm-static:CF' \
        > /proc/sys/fs/binfmt_misc/register
fi
echo "binfmt: $(cat /proc/sys/fs/binfmt_misc/qemu-arm 2>/dev/null | tr '\n' ' ')"

exec "$@"
