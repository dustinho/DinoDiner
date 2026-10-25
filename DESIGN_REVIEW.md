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

### Layout pass: smaller numbers, visible total

| # | Finding | Fix |
|---|---|---|
| 8 | The request bubble (164×92, 46 px numerals) took almost a quarter of the screen. | Bubble is 128×56 with 34 px numerals. The multiplying bubble is 176×46. |
| 9 | Nothing showed the current total, so a child had to count berries to compare with the request. | New **total badge**: [berry] N. It hops on every change, turns black when it matches, counts up with the voice while eating, then shows the whole amount. |
| 10 | In Multiplying, a badge next to "3 × 4" read like part of the equation. | Badge moved to the top-left corner, like a scoreboard, well clear of the bubble. |
| 11 | Two-digit totals ("10", "25") overflowed the badge. | Badge widened to 92 px. A test checks both badges stay on screen and clear of the bubble. |
| 12 | Request, prompt and total were in different places in each game. | Same top row in both games: request bubble top-left (tail down to the T-Rex), crank/A prompt in the middle, total badge top-right. A test checks the order. |

### UX pass: dinos vs. row boxes

| # | Finding | Fix |
|---|---|---|
| 13 | Party dinos' heads touched or overlapped the left edge of their row box (the sprite ended exactly where the box began), worst while hopping. | Cells are 32 px apart instead of 34 (berries are 30), so the grid could shift right. There's now a fixed 5 px gap between each dino and its row, still close enough to read as "my row". A test enforces the gap and checks that a 5-wide row still fits on screen. |
| 14 | The berry inset inside a cell was hard-coded. | Derived from the cell pitch, so the grid can be retuned in one place. |
| 15 | The tray looked heavy. 2–3 px solid box outlines and 50% dotted cells competed with the strawberries. | Tray and row boxes keep their white fill (so the berries stand out from the jungle) but have just a thin dotted edge. Empty cells are faint 25% dots. The strawberries are now the boldest thing on the tray. Check on hardware that the 25% cell dots are still visible on the reflective screen. |

### Layout pass: one axis, centred total

| # | Finding | Fix |
|---|---|---|
| 16 | The request bubble (56 px tall) and total badge (44 px) sat at different heights, so the top row looked ragged. | Both are 48 px tall with the same top edge in both games. A test enforces it. |
| 17 | The total's number was pushed off-centre by a small strawberry icon, which also repeated the tray right below. | Icon removed. The number is centred in its box and hops inside the box, so the box never leaves the shared line. |
| 18 | The total sat in a corner, not visibly tied to the berries it counts. | The box is centred over the strawberries: the whole tray when counting, the current rows when multiplying (it follows "each"). A test checks it for every row width. |
| 19 | In Counting, the tray sat about 90 px below its total. | Tray raised to just under the total and moved right to clear the T-Rex's "!" marks. |
| 20 | A narrow multiplying grid left no room for the prompt between the bubble and the total. | Prompt has a fixed spot under the bubble, above the T-Rex's "!" marks. A test checks it clears both boxes. |

| 21 | In Multiplying, the request and total sat side by side, but nothing said they were two halves of one equation. | An **=** sign sits on the shared line: [dino] 3 × [berry] 4 = 12. A test checks there's room for it at every row width. |
| 22 | A permanent "=" made a partial tray read as a false statement ("3 × 4 = 6"). | The "=" only appears once the total is right. It's bigger (23×17) and sits right next to the total. |
| 23 | At the top level, watching the grid fill made the answer a matter of "fill the shape" rather than working it out. | **Lock-in on level 3:** the crank picks a number, then A reveals the berries one by one and checks. Every give-away (black total, "=", excited T-Rex, smiling friends, empty slots in Multiplying, "just right" nudge) waits until after lock-in. After a wrong answer the grid stays visible so it can be fixed by looking. |

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
