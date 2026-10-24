from PIL import Image, ImageDraw, ImageFont

W, H = 600, 800
S = 2  # supersample
img = Image.new("L", (W * S, H * S), 255)
d = ImageDraw.Draw(img)

# Mountain silhouette (Alpine-ish), high contrast for e-ink.
mountain = [
    (70, 340), (180, 190), (250, 265), (330, 150),
    (420, 250), (530, 340),
]
d.polygon([(x * S, y * S) for x, y in mountain], fill=0)
# Snow caps
d.polygon([(180 * S, 190 * S), (150 * S, 235 * S), (210 * S, 235 * S)], fill=255)
d.polygon([(330 * S, 150 * S), (295 * S, 200 * S), (365 * S, 200 * S)], fill=255)
# Base line
d.rectangle([70 * S, 340 * S, 530 * S, 350 * S], fill=0)

def font(path, size):
    return ImageFont.truetype(path, size * S)

bold = "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"
regular = "/usr/share/fonts/dejavu/DejaVuSans.ttf"

def center(text, y, f, fill=0):
    box = d.textbbox((0, 0), text, font=f)
    w = box[2] - box[0]
    d.text(((W * S - w) / 2, y * S), text, font=f, fill=fill)

center("Alpine Linux", 410, font(bold, 62))
center("Kindle Scribe", 510, font(regular, 34))
center("Chromium 149", 565, font(regular, 34))

# Thin separator
d.rectangle([120 * S, 485 * S, 480 * S, 488 * S], fill=0)

img = img.resize((W, H), Image.Resampling.LANCZOS)
img.save("/tmp/alpine-icon.png", optimize=True)
print("saved", img.size)
