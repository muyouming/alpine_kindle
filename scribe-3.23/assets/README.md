# Build assets

`fetch_assets.sh` copies these files from the Kindle. They are intentionally
not committed (firmware / KMC binaries):

- `fbink.bin` — e-ink refresh helper, from `/mnt/us/libkh/bin/fbink`
- `ld-linux-armhf.so.3`, `libc.so.6`, `libm.so.6` — Kindle glibc, used to run
  the glibc fbink binary inside the musl Alpine chroot

The tracked files in this directory are the bridge scripts used by the build.
