# Design — which mockup is current

One row per screen. **Update this table in the same change as any new design turn**, so it never
disagrees with the canvas. The spec outranks every mockup: a mock is evidence about how things
look, never about how the model works.

- **Live canvas (Turn 13 on):** https://claude.ai/artifact/1SUgDDyWD8W2MerffGrgPM. Its files are mirrored in
  `docs/design/canvas/` (each dark board imports its light board with `theme="dark"`).
- **Claude Design turns 2–12:** `archive/claude-design/` (`T12` = `Pitch Screen T12.dc.html`). Its
  README has Mark's rulings on Turn 12.

Board names: `13A` is Turn 13, board A. `12A` is Turn 12, panel A, in the archive.

| Screen | Current light | Current dark | Rulings that override the mock | Replaces |
|---|---|---|---|---|
| Outcome sheet | **13A** | **13A dark** | §11.1; built option set (`outcome_step.dart`) | 5A, 6A |
| In the dirt (top-down plane) | **13B** | **13B dark** | §11.4: a foot ruler with unsigned labels, no bands, no catcher, no weight on 0 ft; same rect and px-per-x as 15A's zone; depth −2.5 ft … +2.6 ft. Lifting records it, no confirm button (as built). | 3A, 6E |
| Optional actions on the play chain | **13C** | **13C dark** | §15.3: rule calls on runner chips, the batter's included (DIA-018, 2026-11-05) | 11D |
| Field surface (play editor) | **14A** | **14A dark** | §15.5 and §15.1 (v0.60). No runner panel: runners resolve by drag, and neither the spec nor the build has one. | 12A, 11A, 11B, 4A, 6D |
| Field dialogs (trajectory, bunt pair, leave field) | **14B** | **14B dark** | Built labels (Grounder, Popup, Bunt on the ground…) | 12B, 11G bunt inline |
| SAFE / OUT pills | **14B** | **14B dark** | Hold-to-hide completes or never happened (DIA-018) | 12F, 11C |
| Pitch screen chrome (top bar, batter strip, rail) | **15A** (calling), **13A** (result) | **15A dark**, **13A dark** | Two-stop rail with step 2 live from the start (*Jump here — no call*), so there is no Skip call. The LIGHT/DARK toggle sits on the batter strip (DIA-021). | 12C, 11E, 7A–10B chrome |
| Call screen (spots, then the code) | **15A** | **15A dark** | §10.3: the ✓ *beside* the code, the call echoed under it. §23.2: wash = callable, solid = called, dashed = off, ring cells drawn only when callable. §11.4's canvas at 12U: height-bound at 13.2 px/in, plate front edge on the ground line, fading dirt with no drawn rule, both batter's boxes. | 10A, 10B, 12D, 7–9 |
| Post-pitch prompts, sacrifice, can't-record | **14B** | **14B dark** | No *Stayed*. The sacrifice reason line and the split can't-record copy are design ahead of the build. | 12E, 11G |
| Between-pitch field (§15.6) | **15B** | **15B dark** | §15.6: the catcher holds the ball by seed; the reason chips default to Stolen base; Leave field records nothing (§15.5) | — |
| Pitcher and batter scouting | 2B, 2C | 6G, 6H | Not M1 | — |
| Palette, surface ladder, reserved colors | Branding T01–02 | Branding T02 | Built in DIA-016 (`brand_baseline.dart`) | — |
| App icon and splash | Branding T03 (3A, 3C) | Branding T03 (3B, 3D) | — | — |

**Still to draw:** nothing for M1. Scouting (2B/2C, 6G/6H) is post-M1 and gets redrawn when its
ticket comes up.
