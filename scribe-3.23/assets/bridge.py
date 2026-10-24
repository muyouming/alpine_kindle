#!/usr/bin/env python3
# Mirror a 24-bit Xvfb (:1) onto the Kindle 8-bit framebuffer and force e-ink refresh.
import subprocess, struct, sys, time
from PIL import Image

DISPLAY = ":1"
FB = "/dev/fb0"
FBINK = "/usr/local/bin/fbink"
W, H, STRIDE = 1860, 2480, 1872

def capture():
    data = subprocess.check_output(["xwd", "-root", "-display", DISPLAY, "-silent"])
    h = struct.unpack(">25I", data[:100])
    hsize, w, hgt, bpp, bpl, ncolors = h[0], h[4], h[5], h[11], h[12], h[19]
    pos = hsize + ncolors * 12
    pix = data[pos:pos + bpl * hgt]
    if bpp == 24:
        # Alpine xwd emits packed 24-bit pixels with 4-byte row padding.
        img = Image.frombytes("RGB", (w, hgt), pix, "raw", "BGR", bpl)
    else:
        img = Image.frombytes("RGB", (w, hgt), pix, "raw", "BGRX", bpl)
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

def refresh():
    subprocess.call([FBINK, "-s", "top=0,left=0,width=1860,height=2480", "-W", "GC16"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if __name__ == "__main__":
    once = len(sys.argv) > 1 and sys.argv[1] == "once"
    last = None
    while True:
        try:
            img = capture()
            b = img.tobytes()
            if b != last:
                write_fb(img)
                refresh()
                last = b
        except Exception as e:
            print("err", e, flush=True)
        if once:
            break
        time.sleep(1)
