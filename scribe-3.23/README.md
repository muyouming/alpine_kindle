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

The Scribe's native X screen has an **8-bit StaticGray root/default visual**.
The firmware config (`/var/local/xorg.conf`) explicitly sets `Depth 8`,
`Visual "StaticGray"`, driver `mtk` and `FormatEPDC "Y8"`; `/dev/fb0` is
8 bpp. `xdpyinfo` also exposes a **32-bit TrueColor visual** (`0x4e`), but
Xephyr 21.1.23 still falls back to the host root depth for requested 16/24/32
bit screens (tested), so there is no usable nested 24/32-bit screen.

This image therefore uses:

- `Xvfb :1 -screen 0 1860x2480x24`
- `bridge.py`: reads the Xvfb `-fbdir` XWD file, diffs the changed rectangle, writes `/dev/fb0`, then refreshes with fast `A2` (idle full `GC16`)
- `touch.py`: `/dev/input/event3` (`pt_mt`) -> `xdotool` on `:1`
- `startgui.sh`: Xephyr mode when `:0` is 24/32-bit, bridge mode otherwise

Verified on this unit:

| Probe | Value |
|---|---|
| `xwininfo -root -display :0` | 1860x2480, depth 8, StaticGray |
| `xdpyinfo -display :0` | root depth 8; extra depth-32 TrueColor visual 0x4e; no depth-24 visual |
| `/var/local/xorg.conf` | `Depth 8`, `Visual "StaticGray"`, `FormatEPDC "Y8"`, driver `mtk` |
| `/sys/class/graphics/fb0/bits_per_pixel` | 8 |
| Xephyr requests `x16`, `x24`, `x32` | all log `requested screen depth not supported, setting to match hosts` |

**Color Kindles are different.** FBInk marks ColorSoft (`SeaBreeze`,
`Bellatrix4`) and Scribe ColorSoft (`Calvados`, `Platcs8`) with
`hasColorPanel`; Kaleido/CFA color features are 32 bpp. This image targets the
monochrome Scribe (`Barolo`, model `0x875`). On a 24/32-bit host root,
`startgui.sh` picks Xephyr and skips the bridge; the bridge constants
(1860x2480, stride 1872, event3) are Scribe-specific, and the bridge writes
8-bit grayscale only (it is not a color path).

The upstart job passes the host depth/geometry to `startgui.sh` and disables
the touchscreen in the host X server while bridge mode owns it. On stop it
re-enables touch, unmounts the image, detaches the loop device, disables zram,
and restarts `lab126_gui`.

## Icon theme

The upstream dotfiles set `org.mate.interface icon-theme=HighContrast`. That
directory in the MATE icon packages has no `index.theme` and only a couple of
icons, so GTK resolves every menu icon to a blank placeholder. The build sets
the icon theme to `ContrastHigh`, which is complete and inherits
`mate`/`hicolor`.

### Why upstream does not need the bridge

Upstream used Chromium 77. We mounted the 2019 image on this Scribe as a
control: its Xephyr (Xorg 1.20) also fell back to an **8-bit TrueColor**
nested screen, and Chromium 77 rendered a local page normally. Chromium 149
rejects the same 8-bit visual with:

```text
ERROR:ui/base/x/x11_util.cc:627] Unsupported visual with rgb mask 0x7, 0x38, 0xc0
```

The bridge is therefore a compatibility layer for modern Chromium dropping
8-bit visual support, not a workaround for the Scribe lacking any 32-bit
surface. Stock Xephyr 21.1.23 still cannot use the Scribe's depth-32 TrueColor
visual for its nested screen (16/24/32 requests all fall back to depth 8),
so Xvfb + framebuffer is the working path for Chromium 149.

## Performance

Bridge mode is optimized for click latency:

- Reads Xvfb's `-fbdir /dev/shm/Xvfb_screen0` directly (an XWD file: 160-byte header + 256*12 colormap, pixel offset 3232) instead of an 18 MB `xwd` round-trip. Capture is ~0.10-0.15 s instead of ~1 s.
- Dirty-rectangle diff + `fbink -W A2` partial refresh (~0.01 s command time); a full `GC16` runs after 2 s of idle to clear ghosting.
- `touch.py` wakes the bridge through `/tmp/bridge-wake` (FIFO), so there is no 1 s polling delay.
- Panel clock seconds are disabled, avoiding a refresh every second.
- CPU governor is set to `performance` while Alpine runs; Chromium uses low-end flags (`--disable-gpu`, one renderer, site isolation off, small caches).
- Measured tap at (250,1120): touch event logged 0.23 s after injection, bridge A2 refresh 0.22 s later (~0.45 s end-to-end including injection). Previously the xwd + 1 s sleep + full GC16 path took 2-3 s. Page-load A2 refresh is ~0.01 s.

See `screenshot-perf.png`.

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

`launcher/Alpine.sh` is a KMC shell-integration scriptlet. Install it with its cover:

```sh
scp -P 2022 launcher/Alpine.sh root@<kindle>:/mnt/us/documents/
ssh -p 2022 root@<kindle> \
  'mkdir -p /mnt/us/documents/Alpine.sh.sdr'
scp -P 2022 launcher/Alpine.sh.sdr/icon.png \
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
- start menu icons render with the `ContrastHigh` icon theme

See `screenshot-final.png`, `screenshot-menu.png`, `screenshot-perf.png` and `launcher-tile.png`.

## Credits

- [schuhumi/alpine_kindle](https://github.com/schuhumi/alpine_kindle) — original
  chroot image and MATE/dotfiles setup (GPL-3.0)
- [ctl4100wl/alpine-mate-better](https://github.com/ctl4100wl/alpine-mate-better)
  — zram/swap note and MATE lockscreen keyboard settings
- KMC/KPM — `fbink`, shell-integration library tiles
