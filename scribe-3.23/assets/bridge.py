#!/usr/bin/env python3
# Fast Xvfb -> Kindle framebuffer bridge.
#
# Reads Xvfb's framebuffer directly from the -fbdir file (no xwd round-trip),
# refreshes only the changed rectangle with the fast A2 waveform, and does a
# full GC16 once the screen has been idle for a moment to clear ghosting.
import mmap, os, select, struct, subprocess, sys, time
from PIL import Image, ImageChops

FB = "/dev/fb0"
FBINK = "/usr/local/bin/fbink"
FB_FILE = "/dev/shm/Xvfb_screen0"
WAKE = "/tmp/bridge-wake"
W, H, STRIDE = 1860, 2480, 1872
REFRESH_MIN = 0.12
IDLE_CLEAN = 2.0
FULL_CLEAN = 30.0
MODE_FAST = os.environ.get("BRIDGE_FAST", "A2")

def log(msg):
    print("%.3f %s" % (time.time(), msg), flush=True)

def open_fb():
    for _ in range(100):
        try:
            fd = os.open(FB_FILE, os.O_RDONLY)
            mm = mmap.mmap(fd, 0, access=mmap.ACCESS_READ)
            os.close(fd)
            return mm
        except (FileNotFoundError, ValueError):
            time.sleep(0.05)
    return None

def capture_mmap(mm):
    # Xvfb -fbdir writes an XWD file: 160-byte header + 256*12-byte colormap
    # before the pixels. Reading it as raw BGRX shifts the image by 808 px.
    h = struct.unpack(">25I", mm[:100])
    hsize, w, hgt, bpp, bpl, ncolors = h[0], h[4], h[5], h[11], h[12], h[19]
    pos = hsize + ncolors * 12
    pix = mm[pos:pos + bpl * hgt]
    mode = "BGR" if bpp == 24 else "BGRX"
    img = Image.frombytes("RGB", (w, hgt), pix, "raw", mode, bpl)
    if (w, hgt) != (W, H):
        try:
            resample = Image.Resampling.LANCZOS
        except AttributeError:
            resample = Image.LANCZOS
        img = img.resize((W, H), resample)
    return img.convert("L")

def capture_xwd():
    data = subprocess.check_output(["xwd", "-root", "-display", ":1", "-silent"])
    h = struct.unpack(">25I", data[:100])
    hsize, w, hgt, bpp, bpl, ncolors = h[0], h[4], h[5], h[11], h[12], h[19]
    pos = hsize + ncolors * 12
    pix = data[pos:pos + bpl * hgt]
    mode = "BGR" if bpp == 24 else "BGRX"
    img = Image.frombytes("RGB", (w, hgt), pix, "raw", mode, bpl)
    if (w, hgt) != (W, H):
        try:
            resample = Image.Resampling.LANCZOS
        except AttributeError:
            resample = Image.LANCZOS
        img = img.resize((W, H), resample)
    return img.convert("L")

def write_fb(img):
    canvas = Image.new("L", (STRIDE, H), 255)
    canvas.paste(img, (0, 0))
    with open(FB, "r+b", buffering=0) as f:
        f.seek(0)
        f.write(canvas.tobytes())

def refresh(box, mode):
    x0, y0, x1, y1 = box
    x0 = max(0, min(W, int(x0)))
    y0 = max(0, min(H, int(y0)))
    x1 = max(0, min(W, int(x1)))
    y1 = max(0, min(H, int(y1)))
    w, h = x1 - x0, y1 - y0
    if w <= 0 or h <= 0:
        return
    t = time.perf_counter()
    subprocess.run(
        [FBINK, "-s", "top=%d,left=%d,width=%d,height=%d" % (y0, x0, w, h), "-W", mode],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    log("refresh %s %d,%d %dx%d %.3fs" % (mode, x0, y0, w, h, time.perf_counter() - t))

def main():
    once = "once" in sys.argv
    mm = open_fb()
    if mm is None:
        log("fbdir missing, falling back to xwd")
    try:
        if not os.path.exists(WAKE):
            os.mkfifo(WAKE)
        wfd = os.open(WAKE, os.O_RDONLY | os.O_NONBLOCK)
    except OSError as e:
        log("wake fifo: %s" % e)
        wfd = None

    last_refreshed = None
    last_refresh = 0.0
    last_change = 0.0
    last_full = 0.0
    a2_dirty = False

    while True:
        t0 = time.perf_counter()
        img = capture_mmap(mm) if mm is not None else capture_xwd()
        cap = time.perf_counter() - t0
        now = time.time()

        if last_refreshed is None:
            box = (0, 0, W, H)
        else:
            box = ImageChops.difference(last_refreshed, img).getbbox()

        if box:
            write_fb(img)
            last_change = now
            if now - last_refresh >= REFRESH_MIN:
                if last_refreshed is None:
                    refresh((0, 0, W, H), "GC16")
                    last_full = now
                    a2_dirty = False
                else:
                    refresh(box, MODE_FAST)
                    a2_dirty = True
                last_refreshed = img
                last_refresh = now
                log("frame %.3fs box=%s" % (cap, box))

        # After the screen settles, do a quality GC16 pass to remove A2 ghosting.
        if last_refreshed is not None and now - last_change > IDLE_CLEAN:
            if a2_dirty or now - last_full > FULL_CLEAN:
                refresh((0, 0, W, H), "GC16")
                last_full = now
                a2_dirty = False

        if once:
            break

        timeout = 0.05 if now - last_change < 1.0 else 0.8
        if wfd is not None:
            try:
                r, _, _ = select.select([wfd], [], [], timeout)
                if r:
                    try:
                        os.read(wfd, 4096)
                    except OSError:
                        pass
                    last_change = time.time()
            except OSError:
                time.sleep(timeout)
        else:
            time.sleep(timeout)

if __name__ == "__main__":
    main()
