#!/usr/bin/env python3
"""Check that every asset main.lua loads exists and is Playdate-friendly.

- images are strictly 1-bit (pure black/white, alpha fully on or off)
- full-screen images are 400x240; launcher card/icon have required sizes
- sounds are mono 16-bit PCM WAV
Usage:  python3 tools/check_assets.py
"""
import os
import re
import sys
import wave
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "source")
errors = []


def check_png(rel, size=None):
    path = os.path.join(SRC, rel + ".png")
    if not os.path.exists(path):
        errors.append("missing image " + rel)
        return
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im)
    if not np.isin(a[..., :3], (0, 255)).all() or not np.isin(a[..., 3], (0, 255)).all():
        errors.append("not 1-bit: " + rel)
    if size and im.size != size:
        errors.append("%s is %dx%d, expected %dx%d" % ((rel,) + im.size + size))


def check_wav(rel):
    path = os.path.join(SRC, rel + ".wav")
    if not os.path.exists(path):
        errors.append("missing sound " + rel)
        return
    with wave.open(path) as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            errors.append("sound not mono 16-bit: " + rel)


main = open(os.path.join(SRC, "main.lua")).read()
game = open(os.path.join(SRC, "game.lua")).read()
for rel in re.findall(r'loadImage\("([^"]+)"\)', main):
    check_png(rel, (400, 240) if rel in ("images/title", "images/play_bg") else None)
for pose in re.search(r'for _, pose in ipairs\(\{([^}]*)\}', main).group(1).split(","):
    check_png("images/trex_" + pose.strip().strip('"'))
for n in range(0, 26):
    check_png("images/numbers/num_%d" % n)
for n in range(1, 6):
    check_png("images/numbers/num_s_%d" % n)
check_png("images/numbers/times")
check_png("images/numbers/equals")
friends = re.findall(r'"(\w+)"', re.search(r"Game.FRIENDS = \{([^}]*)\}", game).group(1))
for name in ["trex"] + friends:
    for pose in ("idle", "chomp", "happy"):
        check_png("images/friends/%s_%s" % (name, pose), (48, 40))
effects = re.search(r"EFFECTS = \{(.*?)\}", main, re.S).group(1)
for name in re.findall(r'"([^"]+)"', effects):
    check_wav("sounds/" + name)
# every voice line game.lua can ask for
voices = ["title", "instructions", "share_intro", "lockin_intro", "hint_empty", "hint_more", "hint_less",
          "hint_ready", "again", "mode_count", "mode_multiply"]
voices += ["yum_%d" % i for i in range(1, 4)] + ["level_%d" % i for i in range(1, 4)]
voices += ["count_%d" % i for i in range(1, 26)] + ["request_%d" % i for i in range(1, 11)]
voices += ["invite_%d" % i for i in range(1, 5)] + ["each_%d" % i for i in range(1, 6)]
voices += ["fact_%d_%d" % (g, e) for g in range(2, 6) for e in range(1, 6)]
for name in voices:
    check_wav("sounds/" + name)
check_png("launcher/card", (350, 155))
check_png("launcher/icon", (32, 32))

if errors:
    print("\n".join(errors))
    sys.exit(1)
print("assets ok")
