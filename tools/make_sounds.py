#!/usr/bin/env python3
"""Generate Dino Diner's speech and sound effects.

Speech uses the Kokoro-82M neural TTS model (Apache-2.0) with the warm
"af_heart" voice, lifted slightly in pitch so the dino sounds young and
friendly.  Effects are soft, rounded synth sounds (no harsh buzzers).

Output: 16-bit mono PCM WAV, 22050 Hz, in source/sounds/.
Replace any file with a real recording of the same name to upgrade.

Usage:  pip install kokoro-onnx soundfile numpy
        python3 tools/make_sounds.py            (everything)
        python3 tools/make_sounds.py yum_2      (just the named speech clips)
The model and voice files (~120 MB) are fetched once from the npm registry
(packages kokoro-q8-shards and kokoro-js) into tools/.cache/.
"""
import glob
import hashlib
import io
import os
import subprocess
import sys
import tarfile
import urllib.request
import wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "source", "sounds")
CACHE = os.path.join(ROOT, "tools", ".cache")
RATE = 22050
VOICE = "af_heart"
PITCH = 1.10        # gentle lift: younger and brighter, not chipmunk
MODEL_SHA = "fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478"

WORDS = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

SPEECH = {
    "title": "Dino Diner! Press A to play!",
    "instructions": "Hi there! I'm a hungry little dino. "
                    "Turn the crank to put strawberries on my tray. Then press A to feed me!",
    "hint_empty": "No strawberries yet! Turn the crank to add some.",
    "hint_more": "Ooh, I need a few more! Turn the crank to add some.",
    "hint_less": "Oopsie, that's too many! Turn the crank back to take some out.",
    "hint_ready": "That's just right! Press A to feed me!",
    "yum_1": "Yum yum yum! Thank you!",
    "yum_2": "{hum} Delicious! You counted perfectly!",
    "yum_3": "Yummy! Thank you, friend!",
    "again": "Press A to play again!",
}
# Kokoro spells "Mmm" out as letters ("em em em"), so "{hum}" is replaced
# by a long hummed /m/ given to the model directly as phonemes.
HUM = "ˈmːːː,"

WORDS += ["eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
          "seventeen", "eighteen", "nineteen", "twenty", "twenty-one", "twenty-two",
          "twenty-three", "twenty-four", "twenty-five"]

# Multiplying game, title-screen choices
SPEECH.update({
    "share_intro": "Let's have a dino party! Every dino gets its own row. "
                   "Give each dino the same number of strawberries!",
    "mode_count": "Counting!",
    "mode_multiply": "Dino party! Multiplying!",
    "level_1": "Level one!",
    "level_2": "Level two!",
    "level_3": "Level three!",
})
for f in range(1, 5):
    SPEECH["invite_%d" % f] = "I invited %s %s!" % (WORDS[f - 1], "friend" if f == 1 else "friends")
for e in range(1, 6):
    SPEECH["each_%d" % e] = "We each want %s %s!" % (
        WORDS[e - 1], "strawberry" if e == 1 else "strawberries")
for g in range(2, 6):
    for e in range(1, 6):
        SPEECH["fact_%d_%d" % (g, e)] = "%s dinos with %s each makes %s!" % (
            WORDS[g - 1].capitalize(), WORDS[e - 1], WORDS[g * e - 1])

for i, w in enumerate(WORDS, 1):
    SPEECH["count_%d" % i] = w.capitalize() + "!"
    if i <= 10:
        SPEECH["request_%d" % i] = "Can I have %s %s, please?" % (
            w, "strawberry" if i == 1 else "strawberries")


# Kokoro's mispronunciations, fixed in the phonemes: (wrong, right).
PRONUNCIATION_FIXES = [
    ("dˈiːnoʊ", "dˈaɪnoʊ"),    # "dee-no" -> "die-no", as in dinosaur
    ("diːnoʊ", "daɪnoʊ"),
    ("pɹˈɛs ɐ", "pɹˈɛs ˈeɪ"),  # "press uh" -> "press A" (the button)
]


def fix_pronunciation(ph):
    for wrong, right in PRONUNCIATION_FIXES:
        ph = ph.replace(wrong, right)
    for wrong, _ in PRONUNCIATION_FIXES:
        assert wrong not in ph, "unfixed pronunciation %r in %r" % (wrong, ph)
    return ph


# ---------------------------------------------------------------- model fetch
def npm_tarball(pkg, version):
    url = "https://registry.npmjs.org/%s/-/%s-%s.tgz" % (pkg, pkg, version)
    data = urllib.request.urlopen(url).read()
    return tarfile.open(fileobj=io.BytesIO(data))


def ensure_model():
    os.makedirs(CACHE, exist_ok=True)
    model = os.path.join(CACHE, "kokoro-q8.onnx")
    voices = os.path.join(CACHE, "voices.npz")
    if not os.path.exists(model):
        tar = npm_tarball("kokoro-q8-shards", "1.0.0")
        parts = [tar.extractfile("package/kokoro-q8.part%d.bin" % i).read() for i in range(6)]
        blob = b"".join(parts)
        assert hashlib.sha256(blob).hexdigest() == MODEL_SHA, "model checksum mismatch"
        open(model, "wb").write(blob)
    if not os.path.exists(voices):
        tar = npm_tarball("kokoro-js", "1.2.1")
        v = {}
        for m in tar.getmembers():
            if m.name.startswith("package/voices/") and m.name.endswith(".bin"):
                raw = tar.extractfile(m).read()
                v[os.path.basename(m.name)[:-4]] = \
                    np.frombuffer(raw, dtype=np.float32).reshape(-1, 1, 256)
        np.savez(voices, **v)
    return model, voices


# ---------------------------------------------------------------- output
def write_wav(path, samples, peak=0.5):
    s = np.asarray(samples, dtype=np.float64)
    m = np.max(np.abs(s)) or 1.0
    s = s / m * peak
    fade = min(len(s) // 4, int(0.008 * RATE))   # no clicks at either end
    if fade:
        ramp = np.linspace(0, 1, fade)
        s[:fade] *= ramp
        s[-fade:] *= ramp[::-1]
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((s * 32767).astype("<i2").tobytes())


def ffmpeg_filter(samples, rate, af):
    raw = np.asarray(samples, dtype="<f4").tobytes()
    p = subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "f32le", "-ar", str(rate),
                        "-ac", "1", "-i", "-", "-af", af, "-ar", str(RATE),
                        "-f", "f32le", "-"], input=raw, capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype="<f4")


def trim_silence(s, thresh=0.01):
    idx = np.nonzero(np.abs(s) > thresh * np.max(np.abs(s)))[0]
    if len(idx) == 0:
        return s
    pad = int(0.03 * RATE)
    return s[max(0, idx[0] - pad): idx[-1] + pad]


def speech(only=None):
    from kokoro_onnx import Kokoro
    model, voices = ensure_model()
    k = Kokoro(model, voices)
    for name, text in SPEECH.items():
        if only and name not in only:
            continue
        speed = 0.95 if name.startswith(("count_", "request_")) else 1.0
        raw = k.tokenizer.phonemize(text.replace("{hum}", "").strip(), "en-us")
        ph = fix_pronunciation(raw)
        if "{hum}" in text:
            ph = HUM + " " + ph
        if ph != raw:
            s, sr = k.create(ph, voice=VOICE, speed=speed, lang="en-us", is_phonemes=True)
        else:
            s, sr = k.create(text, voice=VOICE, speed=speed, lang="en-us")
        # pitch up without changing tempo, then soften the top end a touch
        af = "asetrate=%d,aresample=%d,atempo=%.4f,lowpass=f=7500" % (
            int(sr * PITCH), sr, 1 / PITCH)
        out = trim_silence(ffmpeg_filter(s, sr, af))
        write_wav(os.path.join(OUT, name + ".wav"), out, peak=0.8)


# ---------------------------------------------------------------- effects
def t_axis(dur):
    return np.arange(int(dur * RATE)) / RATE


def bell(freq, dur, decay=8.0):
    """Soft marimba-ish note: sine + quiet octave, exponential decay."""
    t = t_axis(dur)
    tone = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2 * t) \
        + 0.08 * np.sin(2 * np.pi * freq * 3 * t)
    return tone * np.exp(-t * decay)


def glide(f0, f1, dur, decay=10.0):
    t = t_axis(dur)
    f = f0 * (f1 / f0) ** (t / dur)          # exponential (musical) sweep
    ph = 2 * np.pi * np.cumsum(f) / RATE
    return (np.sin(ph) + 0.15 * np.sin(2 * ph)) * np.exp(-t * decay)


def soft_noise(dur, cutoff_kernel, decay, seed):
    rng = np.random.RandomState(seed)
    n = rng.uniform(-1, 1, int(dur * RATE))
    n = np.convolve(n, np.hanning(cutoff_kernel), "same")
    return n * np.exp(-t_axis(dur) * decay)


def mix(*parts):
    n = max(len(p) for _, p in parts)
    out = np.zeros(n)
    for start, p in parts:
        i = int(start * RATE)
        out[i:i + len(p)] += p[:max(0, n - i)]
    return out


def effects():
    # pop: bubbly upward "bloop" as a berry lands in the bowl
    write_wav(os.path.join(OUT, "pop.wav"),
              mix((0, glide(520, 1040, 0.11, 18)), (0.03, bell(1568, 0.12, 30) * 0.25)), 0.45)
    # remove: gentle downward "boop"
    write_wav(os.path.join(OUT, "remove.wav"), glide(700, 380, 0.13, 16), 0.4)
    # chomp: soft cartoon "nom" - a warm low blip with a little crunch
    write_wav(os.path.join(OUT, "chomp.wav"),
              mix((0, glide(330, 220, 0.12, 14)), (0, soft_noise(0.08, 24, 40, 1) * 0.5)), 0.45)
    # chew: two quiet munches
    munch = mix((0, glide(260, 200, 0.07, 30)), (0, soft_noise(0.06, 30, 50, 2) * 0.6))
    write_wav(os.path.join(OUT, "chew.wav"), mix((0, munch), (0.13, munch * 0.8)), 0.3)
    # cheer: happy marimba arpeggio up to a sparkly top note
    notes = [(0.0, 523.25), (0.09, 659.25), (0.18, 783.99), (0.27, 1046.5)]
    parts = [(t, bell(f, 0.5, 7)) for t, f in notes]
    parts += [(0.36, bell(1318.5, 0.7, 5) * 0.6), (0.36, bell(1568.0, 0.7, 5) * 0.4)]
    write_wav(os.path.join(OUT, "cheer.wav"), mix(*parts), 0.5)
    # whoosh: airy swish for a berry flying to the mouth
    n = soft_noise(0.2, 40, 0, 3) * np.sin(np.linspace(0, np.pi, int(0.2 * RATE))) ** 2
    write_wav(os.path.join(OUT, "whoosh.wav"), n, 0.18)
    # bump: soft wooden "tok" when the bowl is already full / empty
    write_wav(os.path.join(OUT, "bump.wav"), bell(392, 0.12, 35), 0.3)


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    if only:                      # e.g. make_sounds.py yum_2  -> just that clip
        speech(only)
        return
    for f in glob.glob(os.path.join(OUT, "*.wav")):
        os.remove(f)
    speech()
    effects()
    print("wrote", len(os.listdir(OUT)), "sounds")


if __name__ == "__main__":
    main()
