# Claude Design archive (2026-08-18 → 2026-11-05)

The design turns produced in standalone Claude Design, exported on 2026-11-05 before that product
closed on 2026-12-14. Kept as an archive. **Nothing in the app reads these files**, and nothing here
outranks the spec: a mock is evidence about how things look, never about how the model works.

From Turn 13 on, design work is done in Claude Code sessions, so the turns can be checked against
the spec and the built code as they are drawn.

## Files

- `Pitch Screen T02–T12.dc.html` — one file per turn. To render them, open them alongside
  `support.js` and `image-slot.js`, which the turns load by relative path. T06 is the dark pass over
  the T02–T05 screens. T12 is the light pass corrected against the brief.
- `Diamond Branding.dc.html` — Turns 01–03 of branding: the chosen direction (1A Infield), the dark
  surface ladder, the reserved colors (Dusk, Rosin, Ejection, Callable), and the app icon and splash.
- `uploads/` — what Design was given: simulator screenshots, a strike-zone reference image, and
  `Diamond design brief.md`, the spec excerpt written for Turn 12.

## How Turn 12's open questions were ruled (Mark, 2026-11-05)

1. The field's own controls: §15.5 is rewritten to the bottom bar (spec v0.60).
2. Possession: 11B's treatment is accepted, and §15.1 is updated to match (v0.60).
3. A mis-tapped Bunt chip needs no exit of its own. Leave field already goes back to the outcome
   sheet with the call and location kept.
4. The code card vs. the ✓: keep §10.3 as written, with the ✓ beside the code. A swipe-to-re-roll
   on a large button risks confirming by accident. User testing may change this.
5. *Stayed* on the wild-pitch prompt: **no.** A wild pitch or passed ball that nobody advanced on
   isn't one, and a pitch in the dirt is already recorded by its location.
6. Batter side: a standing scorer control (`batterSideProvider`), as 12C draws it.
7. Infield fly lives on the ⚾ node, which is the landing node §15.3 names. No conflict.
