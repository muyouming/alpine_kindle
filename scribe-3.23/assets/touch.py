#!/usr/bin/env python3
# Kindle pt_mt touch -> xdotool events on Xvfb :1 (bridge mode)
import os, struct, subprocess, time

DEV = os.environ.get("TOUCH_DEV", "/dev/input/event3")
ENV = dict(os.environ, DISPLAY=":1")
EXIT_FLAG = "/tmp/alpine-exit"

def xdo(*args):
    subprocess.run(["xdotool"] + list(args), env=ENV,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def log(msg):
    print(msg, flush=True)

def toggle_keyboard():
    if not subprocess.run(["sh", "-c", "command -v xvkbd >/dev/null"],
                          stdout=subprocess.DEVNULL).returncode == 0:
        return
    r = subprocess.run(["pgrep", "-x", "xvkbd"], stdout=subprocess.DEVNULL)
    if r.returncode == 0:
        subprocess.run(["pkill", "-x", "xvkbd"], stdout=subprocess.DEVNULL)
        log("keyboard off")
    else:
        subprocess.Popen(["xvkbd", "-geometry", "1860x700+0+1780", "-compact"],
                         env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log("keyboard on")

fd = os.open(DEV, os.O_RDONLY | os.O_NONBLOCK)
EV_SIZE = struct.calcsize("llHHi")
slot = 0
x = y = 0
down = False
first_x = first_y = None
start_t = 0.0

while True:
    try:
        data = os.read(fd, EV_SIZE * 64)
    except BlockingIOError:
        time.sleep(0.01)
        continue
    except OSError:
        time.sleep(0.1)
        continue

    for i in range(0, len(data), EV_SIZE):
        _s, _us, typ, code, val = struct.unpack("llHHi", data[i:i+EV_SIZE])
        if typ != 3:
            continue
        if code == 47:
            slot = val
        elif code == 53 and slot == 0:
            x = val
            if down and first_x is None:
                first_x = x
        elif code == 54 and slot == 0:
            y = val
            if down and first_y is None:
                first_y = y
        elif code == 57 and slot == 0:
            if val >= 0:
                down = True
                first_x = first_y = None
                start_t = time.time()
            elif down:
                down = False
                dt = time.time() - start_t
                sx = x if first_x is None else first_x
                sy = y if first_y is None else first_y
                dx, dy = x - sx, y - sy
                if abs(dx) < 30 and abs(dy) < 30:
                    if dt >= 1.5 and x < 120 and y < 120:
                        open(EXIT_FLAG, "w").write("1")
                        log("exit requested")
                    elif dt < 1.5:
                        if x < 120 and y > 2360:
                            toggle_keyboard()
                        else:
                            xdo("mousemove", str(x), str(y))
                            xdo("click", "1")
                            log("tap %d %d" % (x, y))
                elif abs(dy) > 100 and abs(dx) < 90:
                    n = max(1, abs(dy) // 120)
                    btn = "5" if dy < 0 else "4"
                    for _ in range(n):
                        xdo("click", btn)
                    log("scroll %s x%d" % (btn, n))
    time.sleep(0.005)
