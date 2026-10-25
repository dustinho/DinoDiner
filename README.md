# Dino Diner (Playdate)

A gentle counting and early-multiplication game for preschoolers (ages 3–5).
A hungry baby T-Rex asks for strawberries. The child turns the **crank** to
fill a grid with strawberries, then presses **A** to feed it. No timers,
lives, score or game over. Mistakes get a spoken hint and the child can try
again.

![Gameplay previews](preview/contact_sheet.png)

## Choosing a game (title screen)

| Input | Action |
|---|---|
| D-pad ◀ ▶ | Switch between **Counting** and **Multiplying** |
| D-pad ▲ ▼ | Choose level 1–3 (shown as dots) |
| A | Play |

The voice announces each choice, so a child who can't read can use it too.
The chosen game and levels are **saved** between sessions.

| Level | Counting | Multiplying (dinos × strawberries each) |
|---|---|---|
| 1 | 1–3 | 2 dinos × 1–3 |
| 2 | 1–5 | 2–3 dinos × 1–4 |
| 3 | 1–10 | 2–5 dinos × 1–5 (up to 25) |

Within a game, levels also unlock automatically. A first-try success is
worth 1 point, a corrected one 0.5, and 3 points move up a level. The new
level is saved. In Counting, new numbers are introduced in order (1, 2, 3,
then 4, 5, then 6–10). After that, targets are random and never the same
twice in a row.

## Counting

1. The T-Rex asks for a number. The bubble shows a strawberry and a big
   numeral.
2. Turn the **crank forward** to add strawberries and **backward** to take
   them out. Berries fill a **2×5 grid** (a ten-frame) one at a time, with
   a bubbly sound. A **total badge** above the grid always shows how many
   are on the tray. It hops on every change and turns black when it matches
   the request. Once the crank stops, the voice says the total.
3. When the count matches, the dino gets excited and a pulsing **A** button
   appears. Press **A**. Berries fly into its mouth one at a time while the
   voice counts along. Then it chews and celebrates.
4. Wrong count? The dino tilts its head with a "?" and says *"I need more"*,
   *"That's too many"* or *"No strawberries yet!"*. For too few, the bubble
   blinks. Extra berries are drawn dark and blink after a "too many" answer.
5. After the celebration, press **A** for the next round. The game never
   moves on by itself.

## Multiplying (dino party)

1. The T-Rex invites friends: *"I invited two friends! We each want three
   strawberries!"* The bubble shows **[dino] 3 × [berry] 3**.
2. The friends walk in, one per row: a mini T-Rex, plus a triceratops,
   stegosaurus, brachiosaurus or ankylosaurus. Each row of the grid is as
   many cells wide as each dino wants.
3. The crank fills the grid **row by row**, so the answer is built as an
   array: 3 rows of 3. Each dino hops and smiles when its row is full. The
   total badge in the top-left corner shows the running total and turns
   black when it's right.
4. Press **A**. Each dino eats its whole row in turn while the voice
   skip-counts (*"three, six, nine"*). Then it states the fact: *"Three
   dinos with three each makes nine!"*
5. Mistakes work as in Counting. For too few, the voice also repeats how
   many each dino wants. Extra berries spill into a dark extra row.

## Controls during play

| Input | Action |
|---|---|
| Crank clockwise / counter-clockwise | Add / remove strawberries (10 per turn) |
| A | Feed, or next round after the celebration |
| B or D-pad down | Remove one strawberry |
| D-pad up | Add one strawberry |
| D-pad right | Hear the request again |

When the crank is docked, the SDK's crank indicator is shown. The D-pad
controls work without the crank.

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
  main.lua          Playdate front end: input, audio, saving, drawing
  game.lua          game rules and state machine (no SDK calls; unit-tested)
  pdxinfo           metadata (v1.4)
  images/           1-bit PNG sprites, backgrounds, numerals
  images/friends/   the party dinos (46x40, idle / chomp / happy)
  sounds/           speech + effects (mono 16-bit PCM WAV, 22 kHz)
  launcher/         card.png (350x155), icon.png (32x32)
tools/
  test_game.lua     logic tests + main.lua smoke test against a mocked SDK
  playdate_mock.lua minimal Playdate API mock that records draw calls
  render_preview.py renders recorded draw calls to PNG previews
  check_assets.py   checks every asset main.lua loads (1-bit, sizes, WAV format)
  make_art.py       regenerates the T-Rex, backgrounds, berries and numerals
  make_friends.py   draws the party dinos
  make_sounds.py    regenerates speech (Kokoro TTS) and effects
  reference/        art-direction mockup
preview/            rendered screens (from the mock, not the Simulator)
```

Game states: `title` → `play` → `feeding` → `celebrate` → `play` …

## Tests

```sh
lua5.4 tools/test_game.lua preview/frames     # 25 tests; dumps draw calls
python3 tools/render_preview.py preview/frames preview
python3 tools/check_assets.py
```

The tests cover:

- feeding every quantity from 1 to 10
- fast cranking: one berry per step, capped at 10 and never below 0
- pressing A while crank steps are still queued
- when counts are spoken (no flood of numbers)
- the hints for too few, too many and an empty tray, and recovering from them
- title-screen game/level choice and saved settings (including bad save data)
- every multiplication from 2×1 to 5×5: row-by-row filling, skip-counting
  while eating, and the spoken fact
- grid and friend layout staying on screen
- idle reminders
- the celebration waiting for A
- progression order
- layout bounds
- a full run of `main.lua` through every state against the SDK mock

## Art and audio

- The **T-Rex poses** (idle, blink, excited, curious, chomp, chew, happy),
  and both **backgrounds** are taken from the mockup in
  `tools/reference/` and converted to 1-bit pixels at native resolution.
  Blink and chomp reuse the idle and excited bodies with the eyes closed, so
  the frames line up without jitter.
- **Strawberries** (30×32, plus a 15×16 one for berries shrinking into a
  friend's mouth), **hearts** and **numerals** are drawn by `make_art.py`.
- The **party dinos** (mini T-Rex, triceratops, stegosaurus, brachiosaurus,
  ankylosaurus) are drawn by `make_friends.py`. They're built from simple
  shapes, then hand-placed pixel eyes and mouths are added. The design
  follows the friends reference sheet.
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
