#!/usr/bin/env python3
"""Render draw-call dumps from tools/test_game.lua into PNG previews.

    lua5.4 tools/test_game.lua preview/frames
    python3 tools/render_preview.py preview/frames preview

This re-implements the handful of Playdate drawing calls main.lua uses,
using the real PNG assets.  It is an approximation of the Simulator, good
for checking layout and legibility, not pixel-exact rendering.
"""
import glob
import math
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def render(lines):
    screen = Image.new("L", (400, 240), 255)
    d = ImageDraw.Draw(screen)
    color, width, mode = 0, 1, "copy"
    cache = {}
    for line in lines:
        p = line.rstrip("\n").split("\t")
        op, a = p[0], p[1:]
        n = lambda i: float(a[i])
        c = 0 if color == 0 else 255
        if op == "image":
            path = a[0]
            if path not in cache:
                cache[path] = Image.open(os.path.join(ROOT, "source", path + ".png")).convert("RGBA")
            im = cache[path]
            src = im.convert("L")
            if mode == "inverted":
                src = src.point(lambda v: 255 - v)
            elif mode == "fillWhite":
                src = src.point(lambda v: 255)
            screen.paste(src, (int(n(1)), int(n(2))), im.split()[3])
        elif op == "setColor":
            color = int(n(0))
        elif op == "setLineWidth":
            width = int(n(0))
        elif op == "setImageDrawMode":
            mode = a[0]
        elif op == "fillRect":
            d.rectangle([n(0), n(1), n(0) + n(2) - 1, n(1) + n(3) - 1], fill=c)
        elif op == "fillRoundRect":
            d.rounded_rectangle([n(0), n(1), n(0) + n(2) - 1, n(1) + n(3) - 1], n(4), fill=c)
        elif op == "drawRoundRect":
            d.rounded_rectangle([n(0), n(1), n(0) + n(2) - 1, n(1) + n(3) - 1], n(4),
                                outline=c, width=width)
        elif op == "fillTriangle":
            d.polygon([(n(0), n(1)), (n(2), n(3)), (n(4), n(5))], fill=c)
        elif op == "drawLine":
            d.line([(n(0), n(1)), (n(2), n(3))], fill=c, width=width)
        elif op == "fillCircleAtPoint":
            r = n(2)
            d.ellipse([n(0) - r, n(1) - r, n(0) + r, n(1) + r], fill=c)
        elif op == "drawCircleAtPoint":
            r = n(2)
            d.ellipse([n(0) - r, n(1) - r, n(0) + r, n(1) + r], outline=c, width=width)
        elif op == "drawTextAligned":
            text = a[0].replace("*", "")
            f = ImageFont.truetype(FONT, 14)
            tc = 255 if mode == "fillWhite" else 0
            d.text((n(1), n(2) + 1), text, font=f, fill=tc, anchor="ma")
        elif op == "crankIndicator":
            d.rounded_rectangle([340, 190, 396, 236], 6, fill=255, outline=0, width=2)
            d.text((368, 205), "crank", fill=0, anchor="ma")
    return screen.point(lambda v: 255 if v > 127 else 0)


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    shots = []
    for f in sorted(glob.glob(os.path.join(src, "*.txt"))):
        name = os.path.splitext(os.path.basename(f))[0]
        img = render(open(f).readlines())
        img.save(os.path.join(out, name + ".png"))
        shots.append((name, img))
    # contact sheet at 2x
    cols = 3
    rows = math.ceil(len(shots) / cols)
    sheet = Image.new("L", (cols * 820, rows * 510), 200)
    sd = ImageDraw.Draw(sheet)
    for i, (name, img) in enumerate(shots):
        x, y = (i % cols) * 820 + 10, (i // cols) * 510 + 26
        sheet.paste(img.resize((800, 480), Image.NEAREST), (x, y))
        sd.text((x, y - 18), name, fill=0, font=ImageFont.truetype(FONT, 14))
    sheet.save(os.path.join(out, "contact_sheet.png"))
    print("rendered", len(shots), "frames to", out)


if __name__ == "__main__":
    main()
