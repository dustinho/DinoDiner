#!/usr/bin/env python3
"""Draw the T-Rex's friends as small 1-bit cartoon sprites.

Each dino is one bold silhouette built from simple shapes drawn at 8x,
outlined, then reduced to native 1-bit pixels so the style matches the
thick-outlined, white-filled T-Rex.  Style rules (after the friends
reference sheet): big head, big shiny eye, a blush, chubby legs, and just
one dithered feature per dino.  Faces are hand-placed pixel stamps.
Three poses each: idle, chomp (mouth open) and happy (eyes closed, grin).

Usage:  python3 tools/make_friends.py      (needs Pillow + numpy)
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "source", "images", "friends")
SS = 8                      # supersampling factor
W, H = 48, 40               # sprite size in native pixels (feet on the bottom row)
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


# Hand-placed face pixels: "#" black, "." white, " " leave as is.
# Drawn shapes turn to mush at this size, so faces are stamped.
EYE = [".###.", "##..#", "###.#", "#####", "#####", ".###."]   # big, shiny
EYE_HAPPY = [".###.", "#...#"]                                   # closed arc
SMILE = ["#...#", ".###."]
SMILE_HAPPY = ["#....#", "#....#", ".####."]                     # wide smile
CHOMP = [".###.", "#####", "#####", ".###."]
BLUSH = ["# # ", " # #"]


def face(c, eye, mouth, blush):
    """Where the eye centre, mouth centre and cheek go (stamped last)."""
    c.face = (eye, mouth, blush)


def stamp(out, rows, x, y):
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch == "#":
                out[y + j, x + i] = 0
            elif ch == ".":
                out[y + j, x + i] = 255


def apply_face(c, out):
    (ex, ey), (mx, my), (bx, by) = c.face
    pose = c.pose
    stamp(out, BLUSH, bx - 2, by)
    if pose == "happy":
        stamp(out, EYE_HAPPY, ex - 2, ey - 1)
        stamp(out, SMILE_HAPPY, mx - 3, my - 1)
    else:
        stamp(out, EYE, ex - 2, ey - 3)
        if pose == "chomp":
            stamp(out, CHOMP, mx - 2, my - 2)
        else:
            stamp(out, SMILE, mx - 2, my - 1)
    return out


def legs(c, xs, top):
    """Short, chubby legs with rounded feet."""
    for x in xs:
        c.part(rrect(x - 3.6, top, x + 3.6, H - 1, 2.6))


# Each dino: one bold silhouette, one dithered feature, big head and eye.
# Coordinates are native pixels in a 48x40 box, feet on the bottom row,
# facing right.  MOUTHS (used by game.lua) is filled in from face().

def mini_trex(c):
    c.part(poly((13, 27), (1.5, 34), (3, 37), (16, 35)))         # tail
    for (x, y) in [(11.5, 22), (14.5, 18.5), (18.5, 16)]:         # back spikes
        c.part(poly((x - 2.6, y + 3.5), (x - 0.5, y - 2.5), (x + 2.8, y + 2.5)), 1.2)
        c.shade(poly((x - 1.5, y + 3), (x - 0.5, y - 1), (x + 1.8, y + 2)))
    legs(c, [16], 33)
    c.part(ell(20, 30, 10, 8.5))                                  # body
    legs(c, [24], 34)
    c.part(ell(32.5, 17, 12.5, 10.5))                             # big head
    c.part(ell(29.5, 31.5, 2.6, 1.8), 1.0)                        # tiny arm
    face(c, (33, 15), (41, 22), (31, 21))


def triceratops(c):
    c.part(poly((9, 28), (1, 33), (2.5, 35.5), (11, 35)))        # tail
    legs(c, [10, 22], 32)
    c.part(ell(18, 30, 12, 8))                                    # body
    legs(c, [14, 26], 34)
    c.part(ell(28, 17.5, 10, 11.5))                              # frill
    c.shade(ell(27, 17, 7.5, 9))
    c.part(poly((31.5, 13), (34, 3), (36.5, 4), (36, 14)), 1.2)   # horns
    c.part(poly((37.5, 14), (41.5, 4.5), (43.5, 6), (40.5, 15.5)), 1.2)
    c.part(ell(36.5, 23.5, 9.5, 9), ell(43, 26.5, 4.5, 4))        # head + beak
    c.part(poly((43, 22.5), (46, 18.5), (46.5, 23.5)), 1.0)      # nose horn
    face(c, (36, 21), (42, 29), (33, 27))


def stegosaurus(c):
    c.part(poly((8, 27), (0.5, 23.5), (1.5, 27.5), (9, 34)))     # tail
    c.part(poly((2, 24.5), (1, 19.5), (4.5, 24)), 1.0)           # tail spikes
    c.part(poly((5, 26), (5.5, 21), (7.5, 26.5)), 1.0)
    for (x, top, w) in [(9.5, 15, 4.6), (17, 10.5, 5.6), (24.5, 14, 4.8)]:  # plates
        mid = (top + 25) / 2
        c.part(poly((x - w, 25), (x - w * 0.8, mid), (x, top), (x + w * 0.8, mid), (x + w, 25)), 1.2)
        c.shade(poly((x - w * 0.5, 24), (x, top + 2.5), (x + w * 0.5, 24)))
    legs(c, [10, 22], 32)
    c.part(ell(18, 30, 13, 8.5))                                  # body
    legs(c, [14, 26], 34)
    c.part(ell(37, 26, 9.5, 8.5), ell(43, 28.5, 4.5, 4))          # head + snout
    face(c, (36, 24), (43, 31), (34, 30))


def brachiosaurus(c):
    c.part(poly((7, 30), (0.5, 34.5), (2, 37), (9, 35)))         # tail
    legs(c, [8, 20], 32)
    c.part(ell(14.5, 31, 11, 7.5))                                # body
    c.shade(ell(10.5, 29.5, 3, 2.2))                             # two big spots
    c.shade(ell(17.5, 28.5, 2.6, 2))
    legs(c, [12, 24], 34)
    c.part(poly((19, 29), (26, 16), (32.5, 17), (27, 32)),        # neck + head
           ell(33, 14, 9, 8), ell(40, 16.5, 4.5, 3.8))              # (head kept
    face(c, (33, 13), (40, 19), (30, 18))                          # inside its row)


def ankylosaurus(c):
    c.part(poly((7, 31), (3, 31), (3, 34.5), (8, 35)))           # tail
    c.part(ell(3.4, 32.8, 3.4, 3.6))                              # tail club
    c.shade(ell(3.4, 32.8, 2, 2.2))
    legs(c, [9, 23], 34)
    c.part(lambda d: d.chord([S(3.5), S(19), S(33), S(46)], 180, 360, fill=255))  # shell
    c.shade(lambda d: d.chord([S(6), S(21.5), S(30.5), S(44)], 185, 355, fill=255))
    for (x, y) in [(9, 25), (16.5, 21.5), (24.5, 22.5), (30, 27)]:  # studs
        c.part(ell(x, y, 2, 2), 1.0)
    legs(c, [13, 27], 35)
    c.part(ell(38.5, 29, 9, 8.2), ell(44, 31.5, 3.8, 3.4))        # head + snout
    face(c, (38, 27), (43, 34), (35, 33))


def make(builder, pose):
    c = Canvas()
    c.pose = pose
    builder(c)
    return c, c.render()


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
    mouths = []
    for name, fn in FRIENDS.items():
        for pose in ("idle", "chomp", "happy"):
            c, out = make(fn, pose)
            save(out, os.path.join(OUT, "%s_%s.png" % (name, pose)))
        mouths.append("%s = { %d, %d }" % ((name,) + c.face[1]))
    print("wrote", len(FRIENDS) * 3, "friend sprites")
    print("mouths for game.lua Layout.friendMouth:", ", ".join(mouths))


if __name__ == "__main__":
    main()
