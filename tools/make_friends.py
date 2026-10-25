#!/usr/bin/env python3
"""Draw the T-Rex's friends as small 1-bit cartoon sprites.

Each dino is built from simple shapes (ellipses, polygons) drawn at 8x,
outlined, then reduced to native 1-bit pixels so the style matches the
thick-outlined, white-filled T-Rex.  Three poses each: idle, chomp
(mouth open) and happy (eyes closed, big smile).

Usage:  python3 tools/make_friends.py      (needs Pillow + numpy)
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "source", "images", "friends")
SS = 8                      # supersampling factor
W, H = 46, 40               # sprite size in native pixels (feet on the bottom row)
STROKE = 1.5                # outline width in native pixels


def S(v):
    return v * SS


class Canvas:
    """Paint shapes back to front: each one gets a black outline and a
    white fill, covering whatever was painted before it."""

    def __init__(self):
        self.ink = np.zeros((H * SS, W * SS), bool)     # True = black
        self.alpha = np.zeros((H * SS, W * SS), bool)

    def _mask(self, *draw_fns):
        img = Image.new("L", (W * SS, H * SS), 0)
        d = ImageDraw.Draw(img)
        for fn in draw_fns:
            fn(d)
        return img

    def part(self, *args):
        """One outlined white shape; several draw functions are merged into
        a single silhouette (no outline between them).  A trailing number
        sets the outline width."""
        fns = [a for a in args if callable(a)]
        nums = [a for a in args if not callable(a)]
        stroke = nums[0] if nums else STROKE
        m = self._mask(*fns)
        k = int(stroke * SS) * 2 + 1
        outer = np.asarray(m.filter(ImageFilter.MaxFilter(k))) > 127
        inner = np.asarray(m) > 127
        self.alpha |= outer
        self.ink[outer] = True
        self.ink[inner] = False

    def mark(self, draw_fn, black=True):
        """Draw directly in black (or white) with no outline."""
        m = np.asarray(self._mask(draw_fn)) > 127
        self.alpha |= m
        self.ink[m] = black

    def shade(self, draw_fn):
        """50% dither inside the shape (applied after reduction)."""
        self.shades = getattr(self, "shades", [])
        self.shades.append(self._mask(draw_fn))

    def render(self):
        a = Image.fromarray(self.alpha.astype("uint8") * 255).resize((W, H), Image.BOX)
        k = Image.fromarray(self.ink.astype("uint8") * 255).resize((W, H), Image.BOX)
        a = np.asarray(a) > 100
        ink = np.asarray(k) > 90
        out = np.full((H, W), -1)
        out[a] = 255
        out[a & ink] = 0
        yy, xx = np.indices((H, W))
        for sm in getattr(self, "shades", []):
            m = np.asarray(sm.resize((W, H), Image.BOX)) > 127
            out[m & (out == 255) & ((xx + yy) % 2 == 0)] = 0
        return apply_face(self, out) if hasattr(self, "face") else out


def ell(cx, cy, rx, ry):
    return lambda d: d.ellipse([S(cx - rx), S(cy - ry), S(cx + rx), S(cy + ry)], fill=255)


def poly(*pts):
    return lambda d: d.polygon([(S(x), S(y)) for x, y in pts], fill=255)


def rrect(x0, y0, x1, y1, r):
    return lambda d: d.rounded_rectangle([S(x0), S(y0), S(x1), S(y1)], S(r), fill=255)


# Hand-placed face pixels ("#" black, "." white) - drawn shapes turn to
# mush at this size.
EYE = [".##.", "##.#", "####", "####", ".##."]
EYE_HAPPY = [".##.", "#..#", "...."]
SMILE = ["#...#", ".###."]
SMILE_HAPPY = ["#....#", "#....#", ".####."]
CHOMP = [".###.", "#####", "#####", ".###."]


def face(c, ex, ey, mx, my, pose, mouth_w=None):
    """Record where the eye (top-left ex, ey) and mouth go; stamped later."""
    c.face = (round(ex), round(ey), round(mx), round(my), pose)


def stamp(out, rows, x, y):
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch == "#":
                out[y + j, x + i] = 0
            elif ch == ".":
                out[y + j, x + i] = 255


def apply_face(c, out):
    ex, ey, mx, my, pose = c.face
    if pose == "happy":
        stamp(out, EYE_HAPPY, ex - 2, ey)
        stamp(out, SMILE_HAPPY, mx - 3, my - 1)
    else:
        stamp(out, EYE, ex - 2, ey - 2)
        if pose == "chomp":
            stamp(out, CHOMP, mx - 2, my - 1)
        else:
            stamp(out, SMILE, mx - 2, my)
    return out


def legs(c, xs, top, foot=39):
    for x in xs:
        c.part(rrect(x - 3.2, top, x + 3.2, foot, 1.8))


def spots(c, pts):
    for (x, y, rx, ry) in pts:
        c.shade(ell(x, y, rx, ry))


def nostril(c, x, y):
    c.mark(ell(x, y, 0.6, 0.6))


def leaf_plate(c, x, base, top, w):
    """Leaf-shaped back plate: outlined, dithered, with a centre vein."""
    c.part(poly((x - w, base), (x - w * 0.6, (base + top) / 2), (x, top),
                (x + w * 0.6, (base + top) / 2), (x + w, base)), 1.1)
    c.shade(poly((x - w * 0.55, base - 0.5), (x, top + 2), (x + w * 0.55, base - 0.5)))
    c.mark(lambda d: d.line([(S(x), S(base)), (S(x), S(top + 2))], fill=255, width=round(S(0.8))))


def triceratops(pose):
    c = Canvas()
    c.part(poly((10, 27), (1, 31), (3, 33.5), (12, 33)))         # tail
    legs(c, [9, 21], 32)
    c.part(ell(16, 30, 11, 7.5))                                 # body
    spots(c, [(11, 29, 2.5, 1.8), (17, 27, 2, 1.5), (21, 31, 2, 1.5)])
    legs(c, [13, 24], 34)
    c.part(ell(27, 19, 8.5, 10.5))                              # frill
    c.shade(ell(26, 15, 5, 5))
    c.part(poly((32, 15), (35.5, 5.5), (35, 16)), 1.2)          # brow horn (back)
    c.part(ell(35, 24, 8.5, 8.2), ell(41.5, 27.5, 4, 3.6))      # head + beak
    c.part(poly((36.5, 16.5), (42, 7), (39.5, 18)), 1.2)        # brow horn (front)
    c.part(poly((42.5, 24.5), (45.2, 20.5), (44.8, 25.5)), 1.0) # nose horn
    face(c, 33, 23, 41, 28, pose)
    return c.render()


def stegosaurus(pose):
    c = Canvas()
    c.part(poly((9, 27), (0.5, 22), (1.5, 26), (9, 33)))        # tail
    c.part(poly((1.5, 23), (0.5, 18), (3.5, 22.5)), 1.0)        # tail spikes
    c.part(poly((4, 24.5), (4.5, 19.5), (6.5, 25)), 1.0)
    for (x, top, w) in [(7.5, 15, 4), (14, 10.5, 5), (21, 10, 5.2), (27.5, 14.5, 4.2)]:
        leaf_plate(c, x, 23.5, top, w)
    legs(c, [9, 21], 32)
    c.part(ell(16.5, 29, 12, 8))                                 # body
    spots(c, [(10, 27, 2.2, 1.6), (15.5, 25.5, 2, 1.4), (20.5, 28, 2.2, 1.6),
              (13, 31, 1.8, 1.3)])
    legs(c, [13, 24], 34)
    c.part(ell(34, 26, 8.5, 7.8), ell(40, 28.5, 5, 4.2))        # head + snout
    nostril(c, 43, 26.5)
    face(c, 33, 24.5, 40, 30.5, pose)
    return c.render()


def brachiosaurus(pose):
    c = Canvas()
    c.part(poly((8, 29), (0.5, 33), (2, 35), (10, 34)))         # tail
    legs(c, [8, 20], 32)
    c.part(ell(15, 30.5, 10.5, 7))                              # body
    spots(c, [(10, 29, 2.2, 1.5), (15, 27.5, 2, 1.4), (19.5, 30, 2, 1.5)])
    legs(c, [12, 23], 34)
    c.part(poly((20, 28), (27, 10), (33, 11), (26, 31)),         # neck + head + snout
           ell(31.5, 7.5, 7.5, 6.8), ell(38, 9.5, 4.2, 3.6), ell(30, 2.2, 2.8, 2))
    c.shade(ell(27, 19, 1.6, 1.4))
    nostril(c, 40.5, 8)
    face(c, 31, 6, 37.5, 11.5, pose)
    return c.render()


def ankylosaurus(pose):
    c = Canvas()
    c.part(poly((7, 29), (3, 29.5), (3, 32.5), (8, 33)))        # tail
    c.part(ell(3.2, 31, 3.2, 3.4))                              # tail club
    c.shade(ell(3.2, 31, 1.8, 2))
    legs(c, [9, 23], 33)
    for (x, top) in [(9, 18), (15, 15), (21, 14.5), (27, 17)]:
        c.part(poly((x - 2.6, 22.5), (x, top), (x + 2.6, 22.5)), 1.0)   # shell spikes
    c.part(lambda d: d.chord([S(4), S(19), S(32), S(42)], 180, 360, fill=255))  # shell
    c.shade(lambda d: d.chord([S(6.5), S(22), S(29.5), S(40)], 190, 350, fill=255))
    for (x, y) in [(11, 25), (18, 23), (25, 25)]:
        c.part(poly((x - 1.6, y + 1.6), (x, y - 1.6), (x + 1.6, y + 1.6)), 0.9)  # studs
    legs(c, [13, 26], 34)
    c.part(ell(36, 28, 8.2, 7.6), ell(41.5, 30.5, 4, 3.4))      # head + snout
    nostril(c, 44, 29)
    face(c, 35, 26.5, 40.5, 32.5, pose)
    return c.render()


def mini_trex(pose):
    c = Canvas()
    c.part(poly((12, 26), (1, 35), (4, 37), (15, 33)))          # tail
    for (x, y) in [(11, 19), (14.5, 15.5), (18.5, 13.5)]:
        c.part(poly((x - 2.2, y + 3), (x - 1.5, y - 2), (x + 2.2, y + 2)), 1.0)  # spikes
    legs(c, [15], 32)
    c.part(ell(19, 29, 9, 9))                                    # body
    spots(c, [(15, 27, 1.8, 1.3), (17.5, 31, 1.6, 1.2)])
    legs(c, [22], 34)
    c.part(ell(31, 18, 11.5, 9.5))                              # big head
    c.part(ell(28.5, 29.5, 2.4, 1.6), 1.0)                      # little arm
    nostril(c, 41, 15.5)
    face(c, 31, 15, 38, 21.5, pose)
    return c.render()


FRIENDS = {
    "trex": mini_trex,
    "triceratops": triceratops,
    "stegosaurus": stegosaurus,
    "brachiosaurus": brachiosaurus,
    "ankylosaurus": ankylosaurus,
}


def save(a, path):
    rgba = np.zeros(a.shape + (4,), "uint8")
    rgba[..., :3] = np.where(a == 255, 255, 0)[..., None]
    rgba[..., 3] = np.where(a < 0, 0, 255)
    Image.fromarray(rgba, "RGBA").save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in FRIENDS.items():
        for pose in ("idle", "chomp", "happy"):
            save(fn(pose), os.path.join(OUT, "%s_%s.png" % (name, pose)))
    print("wrote", len(FRIENDS) * 3, "friend sprites")


if __name__ == "__main__":
    main()
