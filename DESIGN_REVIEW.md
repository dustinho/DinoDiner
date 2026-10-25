# Design review

## v1.5: Multiplying game and party dinos

Reviewed every screen in `preview/`, both games. The screens are rendered
from main.lua's real draw calls by a mock renderer, not the Playdate
Simulator.

![Screens](preview/contact_sheet.png)

### Fixed in this pass

| # | Finding | Fix |
|---|---|---|
| 1 | Party dinos looked noisy: scattered dither specks for spots, a smudgy "cheek", thin feather-like stegosaurus plates. At 1x it read as dirt, not detail. | Redrawn with one bold silhouette per dino and **exactly one dithered feature**: the frill, plates, shell, back spikes or two big spots. |
| 2 | Heads were about a third of the body. Not cute enough next to the chibi T-Rex. | Heads are now about half the height. Bigger 5×6 shiny eyes with a 2-pixel highlight, a small blush, chubby rounded legs. |
| 3 | The happy face's open grin read as stripes. | Simple wide smile with closed arc eyes. |
| 4 | With five dinos, the brachiosaurus's head poked into the row above. | Head lowered so every dino stays within its own row. Sprites are now 48×40, and mouth targets were updated for the berry flights. |
| 5 | The bubble tail ran into the first row's mini T-Rex. | Tail now points at the big T-Rex. Rows moved down 6 px. |
| 6 | Grid cells shared edges, so the dotted outlines looked broken. | Each cell is inset by 1 px. |
| 7 | The empty-tray hint still said "My bowl is empty". | "No strawberries yet!" |

### Still open

- **Big T-Rex vs. grid in Multiplying:** the host takes the left 40% of
  the screen, so the grid and friends are packed on the right. With 5 rows
  the grid runs to the bottom edge. It works in the preview, but check it
  on hardware.
- **Two T-Rexes:** the host also appears as a mini T-Rex owning row 1
  ("we each want…"). That's clear to adults. Watch whether children read
  the mini one as "me".
- **Triceratops horns** poke 1–2 px into the row above in a full 5-row
  grid. Harmless, but noticeable at 4x.
- **The friends were drawn, not extracted:** they follow the reference
  sheet's style, but adding the sheet as `tools/reference/friends.png`
  would allow extracting the real sprites. The sheet has no triceratops,
  so that one stays drawn either way.
- **Not yet run in the Simulator or on hardware.** This includes the
  speed of the row-by-row eating and the length of the spoken facts
  (about 2 s each).

---

## v1.4 review

Reviewed every screen against the art-direction mockup
(`tools/reference/mockup.png`) and the spec's preschool UX goals. The
screens come from `preview/`, which is rendered from main.lua's real draw
calls by a mock renderer, not the Playdate Simulator.

![Screens](preview/contact_sheet.png)

## Fixed in this pass

| # | Finding | Fix |
|---|---|---|
| 1 | The goal-strawberry row under the bubble repeated what the bowl already shows. Two sets of strawberries to track is more noise than help. | Removed the row. The bubble numeral and the bowl are the only quantities on screen. |
| 2 | Removing the row left dead space between the bubble and the bowl. The bubble and numeral were small next to the mockup's chunky "4". | Bubble is larger (164×92). Numerals are 64 px instead of 46 px. |
| 3 | The crank and A prompts sat in the top-right corner, outside the child's line of sight (bubble → bowl). | Prompts are now centered between the bubble and the bowl, where the berries land. The celebration's "press A" uses the same spot. |
| 4 | The bubble tail ran into the dino's "!" excitement marks. | Tail is re-aimed so its tip clears the marks. |
| 5 | After "need more", the number blinked off, leaving an empty bubble. | The bubble now flips to black with a white numeral. The number stays readable and the change still catches the eye. |
| 6 | Without the slot row, "too many" had no visual cue. | Extra berries are drawn dark in the bowl and blink after a "too many" answer. |
| 7 | **Audio:** the espeak voice was robotic, and the effects were raw square and sine blips with hard edges. | New warm neural voice (Kokoro `af_heart`, lifted slightly in pitch) and friendlier wording ("Ooh, I need a few more!", "Oopsie, that's too many!"). Effects are rebuilt as soft bloops, boops, noms and a marimba cheer, with fades on every clip. |

## Still open (needs hardware or a judgment call)

- **10 berries in the bowl:** the front row hides the lower half of the
  back row. All ten are still countable in the preview, but check this on
  the real screen. If it's too busy, shrink the berries to about 26 px or
  use three rows.
- **Numeral style:** Inter ExtraBold is smoother than the chunky pixel
  logo. A custom pixel numeral set would match the mockup more closely.
- **Ground line:** the dashed pebble line under the scene reads a little
  mechanical next to the hand-drawn foliage.
- **Dark "extra" berries** look somewhat like dark hearts at 1x. A small
  "x" or a lift-out animation might read more clearly as "take this one
  out".
- **Audio has not been checked by ear** in this environment. Listen
  especially for:
  - pronunciation of the numbers
  - whether the pitch lift sounds natural
  - balance between the voice and the effects on the Playdate speaker
- **Not yet run in the Simulator or on hardware**, so:
  - crank feel (10 ticks per turn)
  - animation timing
  - legibility on the reflective LCD
