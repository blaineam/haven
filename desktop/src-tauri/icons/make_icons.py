#!/usr/bin/env python3
"""Generate the Tauri icon set for Haven on Windows from the same brand mark as the
Apple/Android icon: a warm violet→pink→amber sunset gradient with a glowing
constellation of connected 'kin' nodes. Produces every size Tauri's bundler wants
(PNG sizes + .ico), plus icon.png/icon.icns placeholders so dev builds resolve."""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(__file__)
BASE = 1024
SS = 4
S = BASE * SS


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, stops):
    n = 180
    small = Image.new("RGB", (n, n))
    px = small.load()
    seg = len(stops) - 1
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            i = min(int(t * seg), seg - 1)
            lt = t * seg - i
            px[x, y] = lerp(stops[i], stops[i + 1], lt)
    return small.resize((size, size), Image.BILINEAR)


def render(size):
    bg = gradient(S, [(124, 58, 237), (236, 72, 153), (245, 158, 11)])
    nodes = [
        (512, 516, 78), (512, 286, 50), (286, 470, 54),
        (738, 470, 54), (372, 736, 48), (652, 736, 48),
    ]
    edges = [(0, 1), (0, 2), (0, 3), (0, 4), (0, 5),
             (1, 2), (1, 3), (2, 4), (3, 5)]

    def sc(p):
        return tuple(v * SS for v in p)

    lines = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    for a, b in edges:
        x1, y1, _ = nodes[a]
        x2, y2, _ = nodes[b]
        ld.line([sc((x1, y1)), sc((x2, y2))], fill=(255, 255, 255, 150), width=11 * SS)

    discs = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dd = ImageDraw.Draw(discs)
    for x, y, r in nodes:
        cx, cy, rr = x * SS, y * SS, r * SS
        dd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(255, 255, 255, 255))

    glow = Image.alpha_composite(lines, discs).filter(ImageFilter.GaussianBlur(radius=26 * SS))
    canvas = bg.convert("RGBA")
    canvas = Image.alpha_composite(canvas, glow)
    canvas = Image.alpha_composite(canvas, lines)
    canvas = Image.alpha_composite(canvas, discs)
    return canvas.resize((size, size), Image.LANCZOS)


def main():
    master = render(BASE)
    # PNG sizes Tauri references.
    sizes = {
        "32x32.png": 32,
        "128x128.png": 128,
        "128x128@2x.png": 256,
        "icon.png": 512,
        "Square30x30Logo.png": 30,
        "Square44x44Logo.png": 44,
        "Square71x71Logo.png": 71,
        "Square89x89Logo.png": 89,
        "Square107x107Logo.png": 107,
        "Square142x142Logo.png": 142,
        "Square150x150Logo.png": 150,
        "Square284x284Logo.png": 284,
        "Square310x310Logo.png": 310,
        "StoreLogo.png": 50,
    }
    for name, sz in sizes.items():
        master.resize((sz, sz), Image.LANCZOS).save(os.path.join(HERE, name), "PNG")
    # Windows .ico (multi-size).
    master.save(os.path.join(HERE, "icon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    # macOS .icns so `tauri dev` on the host resolves it too.
    try:
        master.save(os.path.join(HERE, "icon.icns"))
    except Exception:
        # Pillow may lack icns writer; the .png/.ico are what matter for Windows.
        pass
    print("wrote icon set to", HERE)


if __name__ == "__main__":
    main()
