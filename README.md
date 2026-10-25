# Dino Diner v1.2 — Playdate

A gentle counting game for a preschooler. Help a friendly **T-Rex eat 1–10 berries** using the Playdate crank. Designed for children who cannot read yet.

## Play

1. Press **A** to start. The voice explains how to play and asks for a number of berries.
2. Turn the **crank clockwise** to add berries; turn backwards to take berries away. Each berry appears in its own spot in the bowl, with a pop. After turning slows, the voice says the current total.
3. Press **A** to feed the T-Rex. Berries fly from the bowl into its mouth, with chewing sounds. A mismatch gives spoken guidance, never a loss or time penalty.
4. Press **A** after the celebration to start another round. The game *does not* advance on its own.

Numbers are introduced 1–3, then 4–5, then 6–10, before mixing all ten. Corrected answers count toward unlocking new numbers, but more slowly than first-try answers. Counting uses a consistent 2×5 arrangement, with no target-dot overlays.

| Control | Action |
|---|---|
| Crank clockwise/counterclockwise | Add/remove berries |
| A | Start, feed, or advance after celebration |
| B / D-pad down | Remove a berry |
| D-pad up | Add a berry, no crank necessary |
| D-pad right | Repeat the spoken request |

A press of **A** while a fast crank turn is still being animated is held until the pending berries are in the bowl. This avoids evaluating a partial count.

## Build

The archive is **source code, not a sideload-ready game**. Install the official [Playdate SDK](https://play.date/dev/) for your platform, then in the `DinoDiner` folder run:

```sh
pdc source DinoDiner.pdx
```

Load the generated `DinoDiner.pdx` folder in the Playdate Simulator. To use a physical device, transfer the compiled game with the Simulator or zip the compiled `.pdx` directory for the [Playdate sideload page](https://play.date/account/sideload/).

The Playdate SDK and Simulator were **not available in the build environment** that created v1.1. Gameplay was run with a mocked Playdate API using Lua, and visuals were checked through a draw-call renderer, but there is no claim of an SDK compile, Simulator run, or physical-device acceptance test.

## Tests and assets

- `source/main.lua`: game logic, rendering, crank handling, and sound.
- `source/images`: seven expressive T-Rex poses, true strawberry pixel sprites, logo, and numeral art.
- `source/sounds`: synthetic English speech plus short berry/chew effects; pre-generated and bundled.
- `tools/test_game.lua`: no-SDK deterministic gameplay and audio regression tests.
- `tools/capture.lua` and `tools/render_preview.py`: layout renderer based on the game's actual draw calls, not a Playdate Simulator screenshot.
- `tools/check_assets.py`: verifies PNG dimensions and all WAV sound files.
- `tools/make_assets.py`: optional logo, number art, speech, and sprite regeneration.
- `tools/make_creature_sprites.py`: deterministic 1-bit character and strawberry sprite generation (Pillow and CairoSVG). Requires Pillow, CairoSVG, espeak, and ffmpeg; bundled assets make it unnecessary for ordinary builds.
- `DESIGN_REVIEW.md`: findings, fix rounds, checks, and remaining verification risks.

You can run the behavior tests with `lua tools/test_game.lua source/main.lua` or `texlua --luaonly tools/test_game.lua source/main.lua`. For visual checks use `python tools/render_preview.py` and `python tools/check_assets.py` (Pillow required). On Windows, install those tools separately only if you want to regenerate or test the source; **they are not necessary to build with `pdc`**.

To replace the computer-generated voice, record replacements for the WAV files using the same names, preferably mono ADPCM WAV at 22050 Hz.

## Visual art update (v1.2)

The baby T-Rex is now drawn as seven registration-matched poses: idle, blink, excited, curious, chomp, chew, and happy. All original sprites use hard 1-bit pixels and fit the existing 204×166 sprite bounds. The strawberries are distinct 26×26 seeded fruit with a pointed bottom and leafy crown, rather than generic round berries. The small fruit is used in the bowl and flying feed animation; the 104×104 enlarged copy is provided for asset inspection. Visual review files include `asset-review-sprites.png` and `preview-ten.png`. These previews were rendered by a draw-call harness, **not** the official Playdate Simulator.