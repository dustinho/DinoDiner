#!/usr/bin/env python3
"""Generate Dino Diner's speech (espeak-ng) and sound effects.

Output: 16-bit mono PCM WAV, 22050 Hz, in source/sounds/.
Replace any file with a real voice recording of the same name to upgrade.
Usage:  python3 tools/make_sounds.py   (needs espeak-ng, ffmpeg, numpy)
"""
import os
import subprocess
import tempfile
import wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "source", "sounds")
RATE = 22050
WORDS = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

SPEECH = {
    "title": "Dino Diner! Press A to play!",
    "instructions": "Hi! I'm a hungry dino. Turn the crank to put strawberries in the bowl. "
                    "Then press A to feed me!",
    "hint_empty": "The bowl is empty. Turn the crank to add strawberries!",
    "hint_more": "Hmm, I need more. Turn the crank forward to add some!",
    "hint_less": "Oops, that's too many! Turn the crank back to take some out.",
    "hint_ready": "That's just right! Press A to feed me!",
    "yum_1": "Yum yum yum! Thank you!",
    "yum_2": "Delicious! You counted perfectly!",
    "yum_3": "Mmm, so tasty! Thank you, friend!",
    "again": "Press A to play again!",
}
for i, w in enumerate(WORDS, 1):
    SPEECH["count_%d" % i] = w + "!"
    SPEECH["request_%d" % i] = "Can I have %s %s, please?" % (
        w, "strawberry" if i == 1 else "strawberries")


def write_wav(path, samples):
    s = np.clip(samples, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((s * 32000).astype("<i2").tobytes())


def speak(name, text):
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "raw.wav")
        subprocess.run(["espeak-ng", "-v", "en-us+f3", "-s", "135", "-p", "62",
                        "-a", "160", "-w", raw, text], check=True)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", raw,
                        "-af", "silenceremove=start_periods=1:start_threshold=-45dB,"
                               "areverse,silenceremove=start_periods=1:start_threshold=-45dB,"
                               "areverse,loudnorm=I=-16:TP=-2",
                        "-ac", "1", "-ar", str(RATE), "-sample_fmt", "s16",
                        os.path.join(OUT, name + ".wav")], check=True)


def env(n, attack=0.005, release=0.06):
    t = np.arange(n) / RATE
    a = np.minimum(1, t / attack)
    r = np.minimum(1, (n / RATE - t) / release)
    return a * np.clip(r, 0, 1)


def tone(f0, f1, dur, wave_fn=np.sin, vol=0.6):
    n = int(dur * RATE)
    f = np.linspace(f0, f1, n)
    ph = 2 * np.pi * np.cumsum(f) / RATE
    return wave_fn(ph) * env(n) * vol


def effects():
    rng = np.random.RandomState(3)
    # pop: quick upward blip
    write_wav(os.path.join(OUT, "pop.wav"), tone(420, 1150, 0.075))
    # remove: soft downward blip
    write_wav(os.path.join(OUT, "remove.wav"), tone(700, 260, 0.09, vol=0.45))
    # chomp: low thump + crunchy noise burst
    n = int(0.16 * RATE)
    noise = rng.uniform(-1, 1, n) * np.exp(-np.arange(n) / (0.03 * RATE))
    thump = tone(160, 60, 0.16, vol=0.8)
    write_wav(os.path.join(OUT, "chomp.wav"), thump + noise * 0.5)
    # chew: two soft munches
    n = int(0.09 * RATE)
    munch = rng.uniform(-1, 1, n) * np.exp(-np.arange(n) / (0.02 * RATE)) * 0.35 + \
        tone(120, 90, 0.09, vol=0.4)
    write_wav(os.path.join(OUT, "chew.wav"),
              np.concatenate([munch, np.zeros(int(0.07 * RATE)), munch * 0.8]))
    # cheer: happy major arpeggio
    notes = [523.25, 659.25, 783.99, 1046.5]
    sq = lambda ph: np.sign(np.sin(ph)) * 0.5 + np.sin(ph) * 0.5
    write_wav(os.path.join(OUT, "cheer.wav"),
              np.concatenate([tone(f, f, 0.09, sq, 0.35) for f in notes] +
                             [tone(1046.5, 1046.5, 0.25, sq, 0.35)]))
    # whoosh: for a berry flying to the mouth
    n = int(0.18 * RATE)
    w = rng.uniform(-1, 1, n)
    w = np.convolve(w, np.ones(12) / 12, "same") * np.sin(np.linspace(0, np.pi, n)) * 0.5
    write_wav(os.path.join(OUT, "whoosh.wav"), w)
    # bump: gentle "can't go further" thud (0 or 10 reached)
    write_wav(os.path.join(OUT, "bump.wav"), tone(220, 180, 0.07, vol=0.35))


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, text in SPEECH.items():
        speak(name, text)
    effects()
    print("wrote", len(os.listdir(OUT)), "sounds")


if __name__ == "__main__":
    main()
