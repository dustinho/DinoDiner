# Dino Diner (Playdate)

A gentle counting game for preschoolers (ages 3–5). A hungry baby T-Rex asks
for 1–10 strawberries. The child turns the **crank** to put strawberries in
the bowl, then presses **A** to feed it. No timers, lives, score or game
over. Mistakes get a spoken hint and the child can try again.

![Gameplay previews](preview/contact_sheet.png)

## How to play

1. Press **A** on the title screen. On the first round the dino explains
   how to play, then asks for a number. The speech bubble shows a big
   numeral next to a strawberry.
2. Turn the **crank forward** to add strawberries and **backward** to take
   them out. Each berry pops into the bowl by itself with a bubbly sound.
   Once the crank stops, the voice says the total.
3. When the count matches, the dino gets excited and a pulsing **A** button
   appears. Press **A**. Berries fly into its mouth one at a time while the
   voice counts along. Then it chews and celebrates.
4. Wrong count? The dino tilts its head with a "?" and says *"I need more"*,
   *"That's too many"* or *"The bowl is empty"*. For too few, the bubble
   blinks to draw the eye back to the number. Extra berries beyond the
   request are drawn dark in the bowl, and blink after a "too many" answer.
5. After the celebration, press **A** for the next round. The game never
   moves on by itself.

| Input | Action |
|---|---|
| Crank clockwise / counter-clockwise | Add / remove strawberries (10 per turn) |
| A | Start, feed, next round after the celebration |
| B or D-pad down | Remove one strawberry |
| D-pad up | Add one strawberry |
| D-pad right | Hear the request again |

When the crank is docked, the SDK's crank indicator is shown. The D-pad
controls work without the crank.

### Learning progression

| Stage | Numbers | Unlocks |
|---|---|---|
| 1 | 1–3 | start |
| 2 | 1–5 | after 3 points |
| 3 | 1–10 | after 3 more points |

New numbers are introduced in order (1, 2, 3, then 4, 5, then 6–10). After
that, targets are random within the stage and never the same twice in a
row. A first-try success is worth 1 point, a corrected one 0.5. Progress is
applied when A is pressed after the celebration. It is **not saved**:
restarting the game starts at stage 1.

## Build

You need the official [Playdate SDK](https://play.date/dev/).

```sh
./build.sh          # or build.bat on Windows; runs: pdc source DinoDiner.pdx
```

Open `DinoDiner.pdx` in the Playdate Simulator, or sideload it to a
device.

## Project layout

```text
source/
  main.lua          Playdate front end: input, audio, drawing
  game.lua          game rules and state machine (no SDK calls; unit-tested)
  pdxinfo           metadata (v1.4)
  images/           1-bit PNG sprites, backgrounds, numerals
  sounds/           speech + effects (mono 16-bit PCM WAV, 22 kHz)
  launcher/         card.png (350x155), icon.png (32x32)
tools/
  test_game.lua     logic tests + main.lua smoke test against a mocked SDK
  playdate_mock.lua minimal Playdate API mock that records draw calls
  render_preview.py renders recorded draw calls to PNG previews
  check_assets.py   checks every asset main.lua loads (1-bit, sizes, WAV format)
  make_art.py       regenerates all art from tools/reference/mockup.png
  make_sounds.py    regenerates speech (Kokoro TTS) and effects
  reference/        art-direction mockup
preview/            rendered screens (from the mock, not the Simulator)
```

Game states: `title` → `play` → `feeding` → `celebrate` → `play` …

## Tests

```sh
lua5.4 tools/test_game.lua preview/frames     # 16 tests; dumps draw calls
python3 tools/render_preview.py preview/frames preview
python3 tools/check_assets.py
```

The tests cover:

- feeding every quantity from 1 to 10
- fast cranking: one berry per step, capped at 10 and never below 0
- pressing A while crank steps are still queued
- when counts are spoken (no flood of numbers)
- the hints for too few, too many and an empty bowl, and recovering from them
- idle reminders
- the celebration waiting for A
- progression order
- layout bounds
- a full run of `main.lua` through every state against the SDK mock

## Art and audio

- The **T-Rex poses** (idle, blink, excited, curious, chomp, chew, happy),
  both **backgrounds** and the **bowl** are taken from the mockup in
  `tools/reference/` and converted to 1-bit pixels at native resolution.
  Blink and chomp reuse the idle and excited bodies with the eyes closed, so
  the frames line up without jitter.
- **Strawberries** (30×32), **hearts** and **numerals** are drawn by
  `make_art.py`.
- **Speech** uses the Kokoro-82M neural TTS model (Apache-2.0) with the warm
  `af_heart` voice, pitched up slightly so the dino sounds young. The model
  is fetched once from the npm registry into `tools/.cache/` (git-ignored).
  To use a real voice, record files with the same names (`request_N`,
  `count_N`, `hint_*`, `yum_*`, …) as mono WAVs.
- **Effects** are soft synthesized sounds: a bubbly "bloop" for each berry,
  a gentle "boop" for removing one, a soft "nom" for each bite, and a marimba
  arpeggio for the celebration. Every clip fades in and out, so nothing
  clicks.

See [DESIGN_REVIEW.md](DESIGN_REVIEW.md) for the latest design review.

## Verification status

**Verified here:**

- Lua logic and `main.lua` run under Lua 5.4 against a mocked SDK. All 16
  tests pass.
- Every asset passes `check_assets.py`.
- Screen layouts were checked with the draw-call renderer.

**Not yet verified:**

- Compiling with `pdc`. The SDK could not be downloaded in the build
  environment.
- Running in the Simulator or on hardware.
- Crank feel, audio timing, and testing with real children.

The renderer only approximates SDK drawing, for example the system font
used in the A button.

## Known gaps / next steps

- Save progress (`playdate.datastore`) and add a parent menu (difficulty,
  voice on/off) through the System Menu.
- Professional voice recording, music.
- The original v1.4 archive was not available, so this is a fresh
  implementation of the v1.4 spec.
