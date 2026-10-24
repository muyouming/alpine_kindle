# Alpine Linux 3.23.7 + Chromium 149 for Kindle Scribe

A 2026 refresh of [schuhumi/alpine_kindle](https://github.com/schuhumi/alpine_kindle),
built for the Kindle Scribe's 32-bit ARM SoC and its 8-bit X server.

| Component | This build |
|---|---|
| Alpine Linux | 3.23.7 |
| Chromium | 149.0.7827.53 |
| Desktop | MATE 1.28 + Onboard |
| Fonts | Noto CJK / Emoji |
| Swap | 768 MB zram |
| Image | 3.5 GB ext3, 618 MB zip |

## Why Alpine 3.23.7, not 3.24

Alpine 3.24 and edge no longer publish `chromium` for `armv7` (3.24 only ships
it for x86_64 and aarch64). 3.23.7 is the newest stable branch that still has
an armv7 Chromium, and 149 is the newest armv7 build. Using 3.24 would make
`apk add chromium` fail.

## Display bridge

The Scribe's native X server (`:0`) is **8-bit StaticGray**. Chromium 149
rejects 8-bit visuals, and Xephyr cannot create a 24-bit nested screen when
the host has no 24-bit visual. This image therefore uses:

- `Xvfb :1 -screen 0 1860x2480x24`
- `bridge.py`: `xwd` capture -> grayscale -> `/dev/fb0` -> `fbink -W GC16`
- `touch.py`: `/dev/input/event3` (`pt_mt`) -> `xdotool` on `:1`
- `startgui.sh`: Xephyr mode when `:0` is 24/32-bit, bridge mode otherwise

The upstart job passes the host depth/geometry to `startgui.sh` and disables
the touchscreen in the host X server while bridge mode owns it. On stop it
re-enables touch, unmounts the image, detaches the loop device, disables zram,
and restarts `lab126_gui`.

## Build

The bridge needs `fbink` and the Kindle glibc loader/libs. They are not
redistributed here; fetch them from the Kindle:

```sh
cd scribe-3.23
KINDLE=root@192.168.3.179 PORT=2022 ./fetch_assets.sh
```

Then build in Docker (the container registers qemu-arm binfmt; `--privileged`
is required):

```sh
docker build -t alpine-kindle-builder .
docker run --rm --privileged -v "$PWD:/build" -w /build \
    alpine-kindle-builder bash build_image.sh
```

On Docker Desktop with a remote engine where host bind mounts are not shared,
copy the tree in instead:

```sh
docker create --name kindle-build --privileged alpine-kindle-builder
docker cp . kindle-build:/build
docker start kindle-build
docker exec kindle-build bash /build/build_image.sh
docker cp kindle-build:/build/alpine.zip .
docker rm -f kindle-build
```

Output: `alpine.zip` (gitignored). `SIZE_MB` can be overridden, e.g.
`SIZE_MB=3072`.

## Install

```sh
scp -P 2022 alpine.zip root@<kindle>:/mnt/us/
ssh -p 2022 root@<kindle>
cd /mnt/us && unzip -o alpine.zip
mntroot rw
cp /mnt/us/alpine.conf /etc/upstart/alpine.conf
mntroot r
start alpine            # stop alpine returns to the Kindle UI
```

Default user: `alpine` / `alpine`. The text shell is still available via
`sh /mnt/us/alpine.sh`.

## Library launcher

`Alpine.sh` is a KMC shell-integration scriptlet. Install it with its cover:

```sh
scp -P 2022 Alpine.sh root@<kindle>:/mnt/us/documents/
ssh -p 2022 root@<kindle> \
  'mkdir -p /mnt/us/documents/Alpine.sh.sdr'
scp -P 2022 Alpine.sh.sdr/icon.png \
  root@<kindle>:/mnt/us/documents/Alpine.sh.sdr/
ssh -p 2022 root@<kindle> \
  'chmod 777 /mnt/us/documents/Alpine.sh /mnt/us/documents/Alpine.sh.sdr/icon.png'
```

It appears in the library as **Alpine Linux** and toggles
`initctl start alpine` / `initctl stop alpine`.

## Verified on device

- Kindle Scribe, firmware 5.20.1 (`juno_2001_barolo_bellatrix3`)
- `start alpine` -> bridge mode, Xvfb depth 24/TrueColor
- Chromium renders example.com and a Chinese/Japanese/Korean test page
- Chromium sandbox works without `--no-sandbox`
- `touch.py` injected tap logged `tap 700 1500`
- `stop alpine` -> no mounts, no loop devices, no residual processes,
  touch re-enabled, `lab126_gui` running

See `screenshot-final.png` and `screenshot-home.png`.

## Credits

- [schuhumi/alpine_kindle](https://github.com/schuhumi/alpine_kindle) — original
  chroot image and MATE/dotfiles setup (GPL-3.0)
- [ctl4100wl/alpine-mate-better](https://github.com/ctl4100wl/alpine-mate-better)
  — zram/swap note and MATE lockscreen keyboard settings
- KMC/KPM — `fbink`, shell-integration library tiles
