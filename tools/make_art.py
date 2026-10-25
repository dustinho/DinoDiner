#!/usr/bin/env python3
"""Generate Dino Diner's 1-bit Playdate art.

The T-Rex poses and backgrounds are lifted from the art-direction
mockup (tools/reference/mockup.png) and re-quantised to native 1-bit pixels.
Strawberries and numerals are drawn procedurally so they stay crisp at
their small native sizes.

Usage:  python3 tools/make_art.py            (needs Pillow + numpy)
"""
import glob
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOCK = os.path.join(ROOT, "tools", "reference", "mockup.png")
OUT = os.path.join(ROOT, "source", "images")
LAUNCH = os.path.join(ROOT, "source", "launcher")
FONT = "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf"

WHITE, BLACK, CLEAR = 255, 0, -1   # CLEAR = transparent in our int arrays


# ---------------------------------------------------------------- helpers
def quant(img, lo=90, hi=180):
    """Grey -> 1-bit: dark = black, light = white, mid = 50% checkerboard."""
    a = np.asarray(img.convert("L")).astype(int)
    out = np.where(a > hi, WHITE, BLACK)
    yy, xx = np.indices(a.shape)
    mid = (a >= lo) & (a <= hi)
    return np.where(mid, np.where((xx + yy) % 2 == 0, WHITE, BLACK), out)


def scaled(box, scale, mock):
    c = mock.crop(box)
    return c.resize((round(c.width * scale), round(c.height * scale)), Image.LANCZOS)


def clear_outside(a):
    """Make white pixels connected to the border transparent."""
    a = a.copy()
    h, w = a.shape
    seen = np.zeros_like(a, dtype=bool)
    stack = [(y, x) for x in range(w) for y in (0, h - 1)] + \
            [(y, x) for y in range(h) for x in (0, w - 1)]
    while stack:
        y, x = stack.pop()
        if y < 0 or x < 0 or y >= h or x >= w or seen[y, x] or a[y, x] != WHITE:
            continue
        seen[y, x] = True
        stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    a[seen] = CLEAR
    return a


def trim(a):
    ys, xs = np.nonzero(a != CLEAR)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1], xs.min(), ys.min()


def save(a, path):
    """Save int array (WHITE/BLACK/CLEAR) as 1-bit PNG with alpha if needed."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    a = np.asarray(a)
    if (a == CLEAR).any():
        rgba = np.zeros(a.shape + (4,), "uint8")
        rgba[..., :3] = np.where(a == WHITE, 255, 0)[..., None]
        rgba[..., 3] = np.where(a == CLEAR, 0, 255)
        Image.fromarray(rgba, "RGBA").save(path)
    else:
        Image.fromarray(np.where(a == WHITE, 255, 0).astype("uint8")).convert("1").save(path)


def draw_text(a, text, x, y, size, color=BLACK):
    img = Image.new("L", (size * len(text) * 2, size * 2), 0)
    ImageDraw.Draw(img).text((0, 0), text, font=ImageFont.truetype(FONT, size), fill=255)
    m = np.asarray(img) > 127
    ys, xs = np.nonzero(m)
    m = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    a[y:y + m.shape[0], x:x + m.shape[1]][m] = color
    return m.shape


def erode(m):
    p = np.pad(m, 1)
    return m & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]


def text_mask(text, size):
    img = Image.new("L", (size * len(text) * 2, size * 2), 0)
    ImageDraw.Draw(img).text((0, 0), text, font=ImageFont.truetype(FONT, size), fill=255)
    m = np.asarray(img) > 127
    ys, xs = np.nonzero(m)
    return m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


# ---------------------------------------------------------------- T-Rex
DINO_SCALE = 1 / 1.3
# Panels in the mockup's sprite strip, and horizontal shift (in mockup px)
# that registers each pose's feet/tail against the idle pose.
DINO_PANELS = {
    "idle":    ((20, 548, 312, 735), 0),
    "blink":   ((20, 548, 312, 735), 0),   # idle with eye closed (no jitter)
    "excited": ((595, 548, 905, 735), 4.6),
    "chomp":   ((595, 548, 905, 735), 4.6),  # excited mouth, eyes squeezed shut
    "chew":    ((913, 548, 1223, 735), 6.9),
    "happy":   ((1231, 548, 1518, 735), 0),
    "curious": ((20, 548, 312, 735), 0),   # idle + question mark
}
# eye boxes in mockup-panel pixels (x0, y0, x1, y1)
EYE_IDLE = (157, 40, 181, 69)
EYE_EXCITED = (150, 39, 172, 70)


def closed_eye(a, box, s):
    x0, y0, x1, y1 = [round(v * s) for v in box]
    a[y0:y1, x0:x1] = np.where(a[y0:y1, x0:x1] == CLEAR, CLEAR, WHITE)
    # gentle "u" shaped lid line, 2px thick
    w = x1 - x0
    cy = y0 + (y1 - y0) * 0.62
    for i in range(w - 1):
        t = (i / (w - 2)) * 2 - 1
        y = round(cy + 2.5 * (1 - t * t))
        a[y:y + 2, x0 + i] = BLACK


def drop_small_marks(a, max_px=300):
    """Whiten small detached black blobs in the upper-right (effect marks)."""
    h, w = a.shape
    seen = np.zeros(a.shape, bool)
    for sy in range(h):
        for sx in range(w):
            if a[sy, sx] != BLACK or seen[sy, sx]:
                continue
            comp, stack = [], [(sy, sx)]
            seen[sy, sx] = True
            while stack:
                y, x = stack.pop()
                comp.append((y, x))
                for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1),
                               (y + 1, x + 1), (y - 1, x - 1), (y + 1, x - 1), (y - 1, x + 1)):
                    if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and a[ny, nx] == BLACK:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            ys = [c[0] for c in comp]
            xs = [c[1] for c in comp]
            if len(comp) <= max_px and min(xs) > w * 0.62 and max(ys) < h * 0.45:
                for y, x in comp:
                    a[y, x] = WHITE


def make_dino(mock):
    s = DINO_SCALE
    canvas_w = round(300 * s)
    poses = {}
    for name, (box, shift) in DINO_PANELS.items():
        g = scaled(box, s, mock)
        q = quant(g, 90, 180)
        q[:, :2] = WHITE
        q[:, -2:] = WHITE
        q[-1, :] = WHITE
        if name in ("blink",):
            closed_eye(q, EYE_IDLE, s)
        if name == "chomp":
            closed_eye(q, EYE_EXCITED, s)
            drop_small_marks(q)   # no "!" burst while eating
        if name == "curious":
            m = text_mask("?", 30)
            x, y = round(242 * s), 0
            # white halo so it reads on any background
            halo = np.pad(m, 2)
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    halo |= np.roll(np.roll(np.pad(m, 2), dy, 0), dx, 1)
            sub = q[y:y + halo.shape[0], x:x + halo.shape[1]]
            sub[halo[:sub.shape[0], :sub.shape[1]]] = WHITE
            sub[np.pad(m, 2)[:sub.shape[0], :sub.shape[1]]] = BLACK
        q = clear_outside(q)
        c = np.full((q.shape[0], canvas_w), CLEAR)
        dx = round(shift * s)
        w = min(q.shape[1], canvas_w - dx)
        c[:, dx:dx + w] = q[:, :w]
        poses[name] = c
    # common trim so all poses stay registered
    stack = np.stack(list(poses.values()))
    used = (stack != CLEAR).any(0)
    ys, xs = np.nonzero(used)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    for name, c in poses.items():
        save(c[y0:y1, x0:x1], os.path.join(OUT, "trex_%s.png" % name))
    print("trex sprites", x1 - x0, "x", y1 - y0, "origin offset", x0, y0)
    return poses["happy"][y0:y1, x0:x1]


# ---------------------------------------------------------------- strawberries
def vector_berry(scale=1.0):
    """Strawberry drawn as vector shapes at 8x, then reduced to 1-bit.

    Base design is 30x32; `scale` shrinks it for smaller icons.
    Returns (sprite, body_mask, crown_mask)."""
    SS = 8
    W, H = round(30 * scale), round(32 * scale)
    k = SS * scale

    def mask(draw_fn):
        img = Image.new("L", (W * SS, H * SS), 0)
        draw_fn(ImageDraw.Draw(img))
        return np.asarray(img.resize((W, H), Image.BOX)) > 110

    def body_fn(d):
        d.ellipse([0.6 * k, 4.5 * k, 29.4 * k, 25.0 * k], fill=255)
        d.polygon([(2.5 * k, 18.0 * k), (27.5 * k, 18.0 * k), (18.5 * k, 29.5 * k),
                   (11.5 * k, 29.5 * k)], fill=255)
        d.ellipse([10.5 * k, 25.0 * k, 19.5 * k, 31.8 * k], fill=255)

    def crown_fn(d):
        cx, cy = 15 * k, 7.2 * k
        for ang, ln, wd in ((165, 11.0, 3.4), (122, 9.0, 3.4), (90, 7.0, 3.0),
                            (58, 9.0, 3.4), (15, 11.0, 3.4)):
            r = np.radians(ang)
            dx, dy = np.cos(r), np.sin(r)
            px, py = -dy, dx
            tip = (cx + dx * ln * k, cy + dy * ln * k)
            pts = [(cx + px * wd * k / 2, cy + py * wd * k / 2), tip,
                   (cx - px * wd * k / 2, cy - py * wd * k / 2)]
            d.polygon(pts, fill=255)
        d.ellipse([cx - 2.2 * k, cy - 2.0 * k, cx + 2.2 * k, cy + 2.0 * k], fill=255)
        d.line([(cx, cy), (cx + 0.6 * k, 0.4 * k)], fill=255, width=max(1, int(2.4 * k)))

    body = mask(body_fn)
    crown = mask(crown_fn)
    thick = scale > 0.8
    a = np.full(body.shape, CLEAR)
    a[body] = BLACK
    inner = erode(erode(body)) if thick else erode(body)
    a[inner] = WHITE
    yy, xx = np.indices(body.shape)
    band = 3 if thick else 2
    edge_band = inner & ~np.pad(inner, ((0, 0), (0, band)))[:, band:]
    low_band = inner & ~np.pad(inner, ((0, band), (0, 0)))[band:, :]
    right = xx >= W * 0.45
    a[(edge_band | low_band) & right & ((xx + yy) % 2 == 0)] = BLACK
    # seeds on a staggered grid
    step = 5 if thick else 4
    safe = erode(inner) & ~np.pad(edge_band, 0)
    for row, y in enumerate(range(round(11 * scale), H - 3, step)):
        for x in range(2 + (row % 2) * (step // 2), W - 2, step):
            if safe[y, x] and (not thick or safe[y + 1, x]):
                a[y, x] = BLACK
                if thick:
                    a[y + 1, x] = BLACK
    # leaves: white rim where they lie on the fruit, then solid black
    rim = np.zeros_like(crown)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (1, 1), (1, -1)):
        rim |= np.roll(np.roll(crown, dy, 0), dx, 1)
    a[rim & inner & ~crown] = WHITE
    a[crown] = BLACK
    # shine on the upper-left shoulder
    if thick:
        for (x, y) in ((5, 12), (4, 13), (4, 14), (4, 15)):
            if inner[y, x]:
                a[y, x] = WHITE
    return a, body, crown


# ---------------------------------------------------------------- backgrounds
def make_title(mock):
    g = mock.crop((21, 18, 755, 483))
    g = g.resize((400, round(g.height * 400 / g.width)), Image.LANCZOS)
    q = quant(g, 95, 175)[6:246]
    q[176:198, 240:335] = WHITE   # "SETTINGS" (no menus for preschoolers)
    save(q, os.path.join(OUT, "title.png"))
    # logo for asset review / launcher
    logo = q[45:130, 225:370]
    save(logo, os.path.join(OUT, "logo.png"))
    return q


def make_play_bg(mock):
    g = mock.crop((782, 18, 1518, 483))
    g = g.resize((400, round(g.height * 400 / g.width)), Image.LANCZOS)
    q = quant(g, 90, 175)[6:246]
    W = WHITE
    q[0:95, 180:350] = W           # speech bubble
    q[95:142, 180:378] = W         # goal strawberries
    q[66:108, 148:186] = W         # excitement marks
    q[148:240, 166:366] = W        # bowl
    q[92:240, 58:186] = W          # T-Rex body and head
    q[160:240, 14:60] = W          # T-Rex tail
    q[86:95, 105:145] = W          # stray marks left from the mockup
    q[88:98, 362:372] = W
    # re-draw a pebbly ground line where the erased region crossed it
    rng = np.random.RandomState(7)
    x = 14
    while x < 366:
        n = rng.randint(2, 7)
        q[229, x:x + n] = BLACK
        if rng.rand() < 0.3:
            q[231, x + 1:x + 3] = BLACK
        x += n + rng.randint(3, 9)
    save(q, os.path.join(OUT, "play_bg.png"))


# ---------------------------------------------------------------- numerals
def make_numbers():
    """num_N: 0-25 for the request bubble and the running-total badge;
    num_s_N: 1-5 for the multiplying bubble; times: the x sign."""
    def ink(text, size, name):
        m = text_mask(text, size)
        a = np.full(m.shape, CLEAR)
        a[m] = BLACK
        save(a, os.path.join(OUT, "numbers", name + ".png"))
    for f in glob.glob(os.path.join(OUT, "numbers", "*.png")):
        os.remove(f)
    for n in range(0, 26):
        ink(str(n), 46, "num_%d" % n)
    for n in range(1, 6):
        ink(str(n), 36, "num_s_%d" % n)
    ink("×", 26, "times")
    ink("=", 30, "equals")


# ---------------------------------------------------------------- hearts
HEART = [
    ".##...##.",
    "####.####",
    "#########",
    "#########",
    ".#######.",
    "..#####..",
    "...###...",
    "....#....",
]


def big_heart(w=26, h=24):
    """Solid heart with a white shine, from the classic implicit curve."""
    a = np.full((h, w), CLEAR)
    for y in range(h):
        for x in range(w):
            u = (x + 0.5 - w / 2) / (w / 2) * 1.2
            v = -((y + 0.5) / h * 2.5 - 1.25) + 0.05
            if (u * u + v * v - 1) ** 3 - u * u * v ** 3 <= 0:
                a[y, x] = BLACK
    for (x, y) in [(5, 4), (6, 4), (4, 5), (4, 6), (4, 7), (5, 5)]:
        a[y, x] = WHITE
    return a


def ascii_sprite(rows):
    a = np.full((len(rows), len(rows[0])), CLEAR)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == "#":
                a[y, x] = BLACK
    # fill the interior white (anything enclosed)
    filled = np.where(a == BLACK, BLACK, WHITE)
    filled = clear_outside(np.pad(filled, 1, constant_values=WHITE))[1:-1, 1:-1]
    return filled


# ---------------------------------------------------------------- A button
def a_button(d):
    """Black disc of odd diameter d with a white "A" centred to the pixel."""
    yy, xx = np.indices((d, d))
    c = (d - 1) / 2
    disc = (xx - c) ** 2 + (yy - c) ** 2 <= (d / 2) ** 2
    a = np.full((d, d), CLEAR)
    a[disc] = BLACK
    # pick a nearby size whose glyph is odd in both dimensions, so it has a
    # true centre pixel in the odd-sized disc
    base = round(d * 0.62)
    sizes = sorted(range(base - 3, base + 3), key=lambda z: abs(z - base))
    masks = [text_mask("A", z) for z in sizes]
    m = next((m for m in masks if m.shape[0] % 2 and m.shape[1] % 2),
             next((m for m in masks if m.shape[1] % 2), masks[0]))
    h, w = m.shape
    y0, x0 = (d - h) // 2, (d - w) // 2
    a[y0:y0 + h, x0:x0 + w][m] = WHITE
    return a


# ---------------------------------------------------------------- launcher
def make_launcher(mock, title, happy, berry):
    os.makedirs(LAUNCH, exist_ok=True)
    card = np.full((155, 350), WHITE)
    card[:] = title[40:195, 25:375]
    save(card, os.path.join(LAUNCH, "card.png"))
    icon = np.full((32, 32), WHITE)
    h, w = berry.shape
    y, x = (32 - h) // 2, (32 - w) // 2
    sub = icon[y:y + h, x:x + w]
    sub[berry != CLEAR] = berry[berry != CLEAR]
    save(icon, os.path.join(LAUNCH, "icon.png"))


def main():
    mock = Image.open(MOCK).convert("L")
    happy = make_dino(mock)
    berry, _, _ = vector_berry(1.0)
    save(berry, os.path.join(OUT, "strawberry.png"))
    mini, _, _ = vector_berry(0.5)       # berries shrinking into a friend's mouth
    save(mini, os.path.join(OUT, "strawberry_mini.png"))
    title = make_title(mock)
    make_play_bg(mock)
    make_numbers()
    save(ascii_sprite(HEART), os.path.join(OUT, "heart.png"))
    save(big_heart(), os.path.join(OUT, "heart_big.png"))
    save(a_button(25), os.path.join(OUT, "a_button.png"))
    save(a_button(27), os.path.join(OUT, "a_button_big.png"))
    make_launcher(mock, title, happy, berry)


if __name__ == "__main__":
    main()
