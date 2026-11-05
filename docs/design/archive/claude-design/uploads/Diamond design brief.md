# Diamond — brief for the next design turn

Attached below are the parts of Diamond's spec (v0.59) that govern the screens you are designing: the
strike zone's coordinates (§3.1–3.3), pitch calling (§10), the per-pitch loop (§11), sacrifices
(§13.6), the field surface (§15), and the design language (§23). The rest of the spec — the event
schema, sync, scoring derivations, stats, scouting — is deliberately left out; none of it is on these
screens.

## How to use the spec

**The spec wins.** Where a design idea and the spec disagree, do not draw around the spec: flag it as
a question in the turn's notes, and Mark will rule. Most of what needed correcting in Turn 11 was a
rule the spec already settles, which is why it is attached now.

**Stay inside M1.** M1 is one game scored on one device: the pitch loop and the field surface. No
rosters, player names or stats, no scouting, no app menus. Turn 11's at-bat strip (#14 REYES ·
2-for-3) and PITCHER / SCOUT tabs are out of scope; keep the strip to what the scorer needs to enter
the pitch. The live *SCORES AS* line on the field is in — it reads a projection that already exists.

**Light first, then dark.** Get the light versions right this turn. The dark versions come after,
applying Turn 06's dark surface ladder once the light layouts stop moving.

## Decided since Turn 11 — draw these as stated

**Leave field** (Mark, 2026-11-05): returns to the pitch, **with the pitch's entry intact and its
outcome reopened.** The call and the location come back exactly as they were, the outcome sheet is up,
and the scorer chooses the result again — In play again, or Foul if it went foul. Nothing entered is
lost, and the pitch is never left recorded as *In play* with no play. Label and copy should make that
plain: it is "back to this pitch's result", not "throw the play away" and not "leave the pitch". If
anything is on the chain, it asks once before discarding the play.

**Start play over** clears the chain and the runner moves **and brings the trajectory question back**
(§15.5). Turn 11 kept the trajectory; it should not.

**Two passages in the attached text are already superseded**, and will be updated in the spec when
these screens are built — follow this brief, not them:

- §15.5's *"Leaving the field is undo's job, and undo takes the pitch with it"* — replaced by **Leave
  field** above.
- §11.2's mode ladder and *Skip call* — replaced by Turn 10's rail: step 1 *Call* (the code card
  completes it), step 2 *Record*, with Record live from the start for a pitch nobody called. Don't
  redraw Skip call or a mode control.

## Corrections to Turn 11

- **UNDO PITCH on the field.** With a play open, the pitch under it is already recorded, and an undo
  that reaches past the open play is the defect §15.5 describes (it voided the pitch and left the play
  attached to nothing). On the field the top-bar undo must not void the pitch. Show what it does there
  — disabled with a reason, or doing what Leave field does — and say which.
- **+ RULE CALL.** §15.3: rule calls are baserunning facts and live on the runner-consequence menus,
  never on a standing control. Move it onto the runner rows, consistent with your dashed-optional rule.
- **The sacrifice example.** A *caught* fly with a runner scoring is a sacrifice fly by derivation and
  is never asked (§13.6). The question is asked for a **dropped** fly a runner scored on, or a bunt
  that moved a runner. Redraw the example as one of those ("R3 scored on the drop by CF, 1 out").
- **ON THE BASES.** The line under the choice must not state the move as done. On a wild pitch or
  passed ball the advance is a **prompt after the pitch**, never automatic (§11.3): one runner →
  *Took second* in one tap; more than one → *All runners up one*; or go to the field. A stolen base with
  one runner → *Stole second*; with more than one, the field opens directly. Describe what will be asked,
  not what happened.
- **Can't record this pitch.** Keep the pattern — what happened, why, what to do, one way back — but
  use the reasons that can actually occur: *The game is still loading — try again* and *No batter is
  due — the lineup is missing*. (The stolen-base chip is hidden with the bases empty, so that example
  cannot happen.)

## Still open — answer these

1. **Where does Bunt's ground / air live?** On the outcome sheet, Bunt also covers foul bunts and
   takes, where ground or air means nothing; Diamond currently asks ground / air on the field's first
   question once In play is chosen, and the trajectory menu's Bunt opens the same pair. Draw it where
   it belongs, and say why if not there.
2. Anything above you disagree with — flag it rather than drawing around it.

---

# Spec excerpts (v0.59)

## 3. Coordinate Systems

### 3.1 Strike Zone (`ZoneCoord`)

Catcher's perspective (matches how coaches think and how every scouting chart is drawn).

```typescript
interface ZoneCoord {
  x: number;  // -1.0 (inside to RHB... see note) to +1.0; 0 = middle of plate
  y: number;  // 0.0 = bottom of zone, 1.0 = top of zone
}
```

- Normalized to the *batter's* zone, not absolute inches — so heat maps compare across batters of different heights. The zone rectangle is x ∈ [-1, 1], y ∈ [0, 1]; values outside that range are valid and represent pitches out of the zone (e.g., y = -0.4 is below the knees but still airborne, x = 1.8 is well outside).
- **Handedness note:** x is stored in absolute terms (negative = third-base side, positive = first-base side, catcher's view). Projections flip to "inside/outside" using the batter's handedness at render time. Storing absolute and deriving relative avoids corruption when a switch-hitter's side is corrected later.
- **The axes have different scales, and neither is universal.** `x` normalizes against the plate's 17″ width: one x-unit is 8.5″ for everyone. `y` normalizes against this batter's zone height. The frontal-plane render ratio is therefore `8.5″ / zoneHeight` px-per-x-unit per px-per-y-unit — 0.354 at the 12U profile, 0.425 at 10U — and is per batter, never a constant (§11.4).
- **`y_ground`** — the ground plane — sits at `y = −(zoneBottomHeight / zoneHeight)`. It is the boundary below which a pitch cannot still be airborne, and is used as such by §11.1's hinge and §11.4's dirt band.
- **Canonical profiles.** These are the inputs; every geometric quantity elsewhere in the spec is computed from them, never transcribed from a rounded figure in prose:

| Profile | Zone bottom | Zone top | Height | Axis ratio | `y_ground` |
| --- | --- | --- | --- | --- | --- |
| Fastpitch 10U (~52″) | 14.0″ | 34.0″ | 20.0″ | 0.425 | −0.700 |
| **Fastpitch 12U (~58″)** — M1 default | **15.5″** | **39.5″** | **24.0″** | **0.354** | **−0.646** |
| Fastpitch HS (~66″) | 17.5″ | 41.0″ | 23.5″ | 0.362 | −0.745 |

  Until per-batter zone heights land, ship the 12U row as the placeholder and derive per batter thereafter.
  **Planned, not contested:** batter height becomes settable, and the *default* row is chosen by **age level** rather than being hardcoded to 12U. Everything derived from a profile — `y_ground`, the axis ratio, the top-down plane's depth extent, and the batter silhouette (§11.4) — is expressed as a function of these two numbers precisely so that drops in without a second geometry pass.

- **Rounded figures in prose are display, not source.** `y_ground` at 12U is −0.6458 and is written "≈ −0.65" for readability. Tests assert against the value computed from the canonical inputs, never against the rounded text.
- Zone dimensions are a `RuleSet` concern for *rendering* the zone overlay; the normalized coordinates themselves name no sport and no level. That separation is what makes the removal of the second sport (v0.55) a deletion of rows rather than a change to the coordinate system.

### 3.2 Field (`FieldCoord`)

```typescript
interface FieldCoord {
  x: number;  // FEET. Home plate = (0,0). y-axis points at second base / dead center.
  y: number;  // Polar-friendly: bearing θ = atan2(x, y), distance r = √(x²+y²).
              // Negative θ = third-base side. θ beyond ±45° is foul territory.
}
```

- **Absolute feet, not normalized** (revised in v0.6). Because every game carries a `FieldProfile` (§16), "how far was that ball hit" is a real number — 187 feet is 187 feet. The entry canvas renders to the game's actual field, so a tap on the warning track *means* the warning track.
- **Cross-park comparability is derived, not stored:** projections compute `fenceRelativeDepth = r / fenceDistanceAt(θ)` using the game's fence model (§16.2). This beats the old CF-normalization — a 200-foot fly ball is a fence-scraper down the line and a routine out to center, and normalizing along the actual bearing captures that.
- **Foul territory is first-class.** No clamping at ±45°. A foul pop caught behind first base and a foul ball ripped just wide of the third-base bag are both real data points (foul tendencies are scouting gold — a hitter fouling everything off to the opposite field is late).

### 3.3 Pitch Bounce (`BounceCoord`)

For a pitch that hits the dirt before reaching the plate — a physically distinct question from "how low," which `ZoneCoord.y` already answers for pitches that arrive in the air.

```typescript
interface BounceCoord {
  x: number;       // SAME normalized lateral axis as ZoneCoord.x (absolute, catcher's view)
  depth?: number;  // FEET from the front edge of the plate; positive = toward the pitcher
                   // (bounced out front), 0 = front edge, negative = past the back edge
                   // (skipped). Sign convention stated here on purpose.
                   // OPTIONAL — absent = "in the dirt, depth unknown" (§11.1).
}
```

- **Absolute feet, not normalized** — unlike `ZoneCoord.y`, which is normalized because the strike zone varies with batter height, ground geometry doesn't: the plate is 17 inches for everyone, and a bounce four feet out front is four feet out front regardless of who's standing in the box. This makes `depth` directly comparable across batters, pitchers, and games with no transformation.
- **`x` is shared with `ZoneCoord`, not re-derived.** `ZoneCoord.x` is already normalized against the fixed 17″ plate width, not batter height (only `y` varies by batter), so the two coordinate spaces register on the same lateral axis — "she misses arm-side and in the dirt" is one query across both, and a dirt strip renders in lateral register with the zone above it.
- Two planes, not a 3D position: `ZoneCoord` is the frontal plane (lateral × height) a pitch is tapped into when it reaches the plate in the air; `BounceCoord` is the top-down plane (lateral × depth) a pitch is tapped into when it hits the dirt first. They share the lateral axis and nothing else — no perspective projection, no inferred 3D point.
- **`depth` is optional; `x` is not.** §11.1's hinge is reached by a release in the dirt band, which always yields a lateral position, and the second placement that sets depth can be skipped (§11.2's ladder). A `BounceCoord` with `x` alone is therefore a real observation — "she was in the dirt, arm-side" — not a partial record, and is stored as such rather than being padded with a fabricated depth (Core Principle #3). **Absent is never 0**: `depth: 0` means the ball hit the plate's front edge, which is a measurement. Both consumers that don't need depth read fine without it — §4.1's conventional `y_ground` coordinate needs only `x`, and §17.4 needs only that a bounce happened.


## 10. Pitch Calling & Wristband Codes

Diamond replaces the laminated call sheet: the coach taps the call, Diamond displays the three-digit code, the coach yells it, the pitcher (and catcher) look it up on their wristband cards. The intended-pitch data is captured as a byproduct of calling the game — zero added workload.

### 10.1 Call Zones

Coaches call *zones*, not coordinates. Each team configures a **call-zone layout**:

```typescript
interface CallZone {
  id: string;
  label: string;          // "Up-In", "Low-Away", "Chase-High", "Bury-Down", ...
  centroid: ZoneCoord;    // canonical target; classification reference (§17.4)
  bounds: ZoneRect;       // hit region on the calling grid; also the "executed"
                          //   region for command classification (§17.4). Whether
                          //   this is a strike call or a chase call is DERIVED from
                          //   where it sits (centroid outside the zone rect ⇒ chase),
                          //   never stored — see below.
}
```

- **Canonical cells (v0.38).** Call zones are not authored as free rectangles. The plate and its surround are partitioned once, canonically, into a **5×5 grid of 25 cells**: the 3×3 strike-zone grid (§3.1), whose outer ring is the zone's edges — the black — plus one off-the-plate stop beyond it in each direction, corners included. Each axis reads *off-in, in, middle, out, off-out* laterally and *off-low, low, middle, high, off-high* vertically. The corners are what make "too low and too far away" a callable pitch rather than an unnamed gap; most teams will never separate them, and the one that wants them shouldn't have to redraw the model to get them.
- **Ring cells are unbounded in extent but nominal in target.** A ring cell's `bounds` run outward without limit — the partition cannot have a hole, since containment (§17.4) must resolve every point however far off the plate — but its centroid is placed as though the cell had the **same dimensions as an in-zone cell**, sitting immediately beyond the zone edge. The geometric centroid of an unbounded region is undefined, so the target is necessarily nominal; equal dimensions is the simplest choice and the closest to what "off the plate that way" means. The target is therefore *half* a cell beyond the edge, since it sits in that cell's middle: at the 12U canonical profile, ≈2.8″ outside the plate edge laterally (half of a 5.67″ column) and ≈4″ past the knee and armpit vertically (half of an 8″ row), putting off-high ≈43.5″ up and off-low ≈11.5″ up. Figures rounded for display; compute from §3.1. The lateral figure is tight — a chase 2.8″ off the black is very hittable — and is a starting place to be revisited against practice rather than a derived constant.
- **A team's layout is a grouping of those cells, never an independent set.** A 10U team groups an entire edge into one "chase high"; a 14U team leaves those cells separate. `bounds` is *derived* from the grouping, which makes overlapping zones and uncovered gaps unrepresentable rather than merely invalid — and containment classification (§17.4) depends on exactly that, since freeform intent and observation mode both need any point to resolve to one zone.
- **Zones are batter-relative; coordinates are absolute.** A zone's identity, label, and codes are stated from the batter's point of view — "Up-In" is inside to whoever is batting — because the wristband decides it: a code has to mean one thing to the pitcher reading it, and *inside* is that thing. `ZoneCoord` stays absolute in the catcher's view (§3.1), so a relative zone is mirrored to an absolute `intendedLocation` when the pitch is written, using that batter's side. Two consequences follow. `intendedZoneId` aggregates cleanly across a lineup, so §17.4's command rubric compares like with like instead of mixing inside-to-a-lefty with away-to-a-righty. And because the call grid is drawn on the entry canvas itself (§11.4), **nothing mirrors**: the geometry stays absolute and fixed, and it is only the *label* that resolves — "In" sits at negative x for a right-handed batter and positive for a left-handed one. The never-mirror rule (§11.4, v0.36) is preserved rather than excepted.
- **Grouping is also what keeps intent comparable over time.** A player's history follows them (§22) across age groups whose vocabularies differ. Because every layout groups the same 25 cells, any two roll up to a common frame; independently authored rectangles would not.
- **The callable set is per pitch type, and the coach alone decides it.** The layout defines which zones exist; each pitch type carries its own subset of them. Diamond has no opinion about which locations suit which pitch — a high drop and a low rise are real calls a coach may want, and every one of the 25 cells is available to every pitch type. The default is that all of them are callable for all types; narrowing is always the coach's act, never the app's inference. The matrix is sparse in practice, which is what keeps the card printable — cell count is the sum over calls of their code counts, not the cross product — but nothing enforces sparsity. The call screen offers exactly what the active card can express and never more, since a code the coach can yell must be a code the pitcher can look up; editing a type's zones invalidates the card and requires a regenerate (§10.2).
- **There is no such thing as a waste pitch.** A pitch deliberately thrown off the plate is doing a job — drawing a chase, changing eye level, burying a drop ball on 0-2 — and executing one is execution, not waste. The distinction is load-bearing: it decides whether the pitch counts as a hit target or a miss (§17.4).
- **Chase intent needs no flag — the call's position states it.** A zone whose `centroid` falls outside the strike-zone rect (§3.1) is by definition a call for a ball; one inside is a call for a strike. Nobody calls a location inside the zone hoping for a ball, or outside it hoping for a strike, so a stored `objective` field would be redundant state that can silently contradict the geometry the moment a team redraws a zone. Derived, it can't (Core Principle #3). Centroid, not bounds, decides straddling zones on the corners.
- `PitchThrown.intendedLocation` stores the zone's `centroid`; a new optional field `intendedZoneId` stores the zone identity so projections can aggregate by call zone directly, and so command classification can read the zone's `bounds` (§17.4).
- **Freeform intent capture (v0.18).** The zone-grid flow above is one producer of `intendedLocation`/`intendedZoneId`, not the only one. Contexts without a wristband-code call — solo scoring, a coach calling verbally, observation mode (§19.5) where the opponent's zone layout isn't yours to know — may instead capture `intendedLocation` as a raw freeform tap on the same canvas, leaving `intendedZoneId` null. Both fields are already optional/unconstrained, so no schema change is required. Because `intendedLocation` is no longer guaranteed to equal a zone's stored centroid, projections must not resolve intent by looking up a centroid via `intendedZoneId`. Command classification instead resolves *any* intent point back to a call zone by containment (§17.4) — a freeform tap almost always lands inside one, since the layout covers out-of-zone space too — so one rubric serves both producers.

### 10.2 Code System

```typescript
interface WristbandCard {
  id: string;
  teamId: string;
  label: string;              // "vs Millard South 7/26", "Card C"
  createdAt: string;
  pitchEntries: CodeEntry[];      // digit-row grid — "539" = row 5, column 39
  offenseEntries?: CodeEntry[];   // letter-row grid — "B14" (§20.5); print-only
  active: boolean;
}

interface CodeEntry {
  code: string;               // spoken form = grid coordinate (row + column label)
  pitchTypeId?: PitchTypeId;  // pitch entries: type + zone
  callZoneId?: string;
  playId?: string;            // offense entries (§20.5)
                              // all refs null = decoy cell
}
```

- **k codes per call** (default k = 4): every (pitch type × call zone) combination gets multiple codes, randomly assigned. When the coach taps a call, Diamond picks among that call's codes — pseudo-randomly, but never repeating the code just used for the same call. The same "rise, up-in" is 539 one pitch and 217 three pitches later. This is the sign-stealing defense, and it's *better* than a static laminated sheet, where pattern-hunting parents in the stands are a real thing.
- **k is per call, not per card (v0.38, direction).** Calls are not thrown equally often — a coach may call a fastball down-and-away thirty times a game and a rise up-and-in twice — and a code's job is to keep the *frequent* calls from becoming recognizable. Spending the same number of cells on both wastes the card where it matters and under-defends where it counts, so a call's code count should follow how often the team expects to call it. Uniform k is the starting default and the simplest thing a coach can be shown; varying it is the generator's job, and the allocation belongs with wristband setup rather than here. Two consequences to carry forward: card size is the **sum over calls of their code counts** (uniform k makes that the type's zone count × k), and the three-digit format caps the whole card at 9 rows × 90 columns = 810 cells, which the generator must enforce rather than silently emitting four-digit codes.
- **Grid coordinates, randomized contents** (revised v0.10 after studying real-world systems). Cards are read as coordinates — first digit = row (1–9), remaining digits = column label — because lookup must be O(1): a ten-year-old finds row 5, column 39 in two seconds, while scanning a flat list of random numbers between pitches is misery. The security lives in the *contents*: cell assignments are randomized per card, the same call occupies its k cells at unrelated coordinates, and digits carry zero pitch meaning. Letter rows are a supported card option ("C-14") for teams that prefer them.
- **Rotation:** cards regenerate per opponent (or on demand mid-tournament if the coach suspects a leak). Old cards are retained read-only — historical `PitchThrown` events don't reference codes at all (only type + zone), so rotation never touches game data.
- **Print/export:** Diamond generates a PDF of wristband inserts — the standard grid sized for common wristband window dimensions (configurable), pitcher and catcher copies, plus a large-print dugout backup. Kill feature for adoption: coaches currently make these in Excel and hate it.
- **Decoys (optional toggle):** pad the card with codes that map to no call, and let the coach yell a decoy with a tap-and-hold. v1.1 candidate; card schema supports it (`CodeEntry.pitchTypeId: null`).

### 10.3 Calling UI

The call screen is two taps: **pitch type** (button row, team's configured arsenal) then **zone** (the grid). Type precedes zone because the zone vocabulary depends on the type (§10.1). The grid's geometry is **fixed and never re-flows** between types — only which cells are callable changes. Muscle memory across 120 pitches is worth more than larger targets. On the second tap, the code renders **huge** — 120pt+, readable at arm's length in sunlight — with the call echoed underneath in small text ("Rise · Up-In · #539"). A re-roll gesture (swipe the code) picks a different code for the same call without re-tapping.

**One accent, and no per-type color (v0.38).** The type row is not color-coded. §23.1.2 allows exactly one accent live at a time, and it belongs to the *selected* type (§23.1.3 — the accent goes to the datum); types are told apart by label and position. Color-coding pitch types is a plausible **review**-surface treatment — reading an at-bat or a game back with types distinguished — where it is categorical encoding in a chart rather than a second accent, and §23.4 makes that a different surface with different rules. It is not a calling-screen treatment.

**No chase-specific gesture (v0.38).** Earlier text gave tap-and-hold the meaning "off the plate that way, don't care exactly where," resolving to the chase zone in that direction. Under §10.1's canonical 25 cells every off-plate location is directly tappable, and a hold could only ever resolve to a cell that is already callable — a code the coach can yell must be a code the pitcher can look up — so the gesture had become a shortcut to a tap. It was also undefined on the center cell, which has no outward direction. Removed.

The pending call persists on screen until the pitch result is entered, then the flow returns to the call screen for the next pitch. Shake-off reality: if the coach changes the call, tapping a new type/zone simply replaces the pending call — nothing is committed to the event stream until the pitch actually happens.

**The checkmark is the pitch-happened signal (v0.40).** Beside the code — or alone in the code's slot for a team calling verbally, which has a pending call but no code to sit next to (§10.2) — a checkmark confirms the call was used and advances the loop to actual-location entry (§11.1). It exists because the transition needs an observable act: nothing else on the surface can tell "the pitch is in the air" from "the coach is still deciding," and a free-standing button below the canvas read as page chrome where the checkmark sits with the artifact it confirms. It appears only once a pending call exists — a half-made call has nothing to confirm, so the coach finishes it, replaces it, or takes §11.2's skip.

**Whose screen this is (v0.39).** The call screen is designed as its operator's *whole job*. At full capture depth that operator is the caller on a secondary device (§12.2's duty bundles); in combined single-operator play it is the scorer, with the ladder (§11.2) and toggles (§12.4) shedding load elsewhere. Nothing about the screen differs between the two — same two taps, same code — only who is holding it.

## 11. Per-Pitch Entry Flow

The loop that runs 120+ times a game. Tap budget per pitch, full mode: **5** (type, zone → code; ✓ pitch thrown; actual location; outcome confirm). The fifth tap is v0.40's honesty about the seam between calling and recording: the pitch *happening* is not something Diamond can observe, so the coach confirms it — the checkmark beside the code (§10.3), which doubles as "this call was the one used."

### 11.1 The Loop

```
┌─► [CALL]    tap type → tap zone → CODE DISPLAYED (yell it)
│   [PITCH HAPPENS]  ✓ beside the code confirms it → on to ACTUAL
│   [ACTUAL]  one tap on the zone canvas = actualLocation; a release in
│             the dirt band hinges the view to a top-down plate plane —
│             a second tap there = bounceLocation (§3.3)
│             Diamond suggests an outcome from context (tap location,
│             count, swing inference impossible → suggestion only):
│             big confirm button + small override row
│   [OUTCOME] confirm (1 tap) or override (1 tap)
│   ├── ball/strike/foul ──────────────► back to CALL (count advances)
│   ├── foul (optional +1 tap) ─► quick field tap for foul coordinates
│   └── in_play ─► [FIELD] trajectory (5 buttons) → ball path, drawn
│                  or implied by the fielder drag (§15.1 v0.43)
│                  → fielding sequence entry → runner resolution
│                  (no location yet? the return offers "record last
│                  pitch" — both orders, see the v0.39 bullet below)
└───────────────────────────────────────◄ back to CALL, next batter/pitch
```

- **Outcome suggestion logic:** location well out of zone → suggest `ball`; in zone → suggest `called_strike` — the suggestion leads the surface as one full-width button. **`in_play` gets the same weight in a row of its own at the bottom, always** (v0.43): it is never suggested (contact isn't inferable from a location) but it is the other outcome that changes everything, opening the whole field surface, so it lives in the same place every time. The override row between them carries the rest of the set (swinging, foul, foul tip, HBP, illegal, catcher's interference). Suggestion ≠ auto-commit — one tap is always required, because the ump's call is the truth, not the location.
- **Unlocated pitches, both orders — and backfill at any time (v0.39, extended v0.53):** on contact the scorer's attention leaves the zone — location-first is often impossible, but implying a skip would throw away the times it isn't. Both orders exist in the loop: the actual-location step stays for the scorer who caught it, and the outcome row is reachable without it — tap `in_play`, score the whole play, and on the loop's return an affordance offers **"record last pitch."** **Two outcomes arm it (v0.53), for one reason: the scorer’s attention left the zone.** On contact that is obvious; on an **uncaught third strike** it is the same fact — the batter is running, and the eye follows her and the ball, not the plate. Nothing else qualifies: arming this for every unlocated pitch would put the affordance on nearly every call screen of a scorer who skips location routinely, which is how a standing offer becomes chrome. The backfill canvas carries the **bounce hinge** in both cases, because the ordinary dropped third strike is a ball in the dirt — an offer that could only record a frontal location would miss the case that motivates it. Maybe the scorer takes it, maybe not; it blocks nothing and dismisses by moving on. The offer never expires: a pitch missing its location can be given one at any time — from the pitch summary between innings, or from the game stream after the game, where someone with the video up can chart every ball in play at leisure (§12.3). All of it is one mechanism: a correction (§6) to the committed `PitchThrown`, the same post-hoc pattern as the batter-action chips — the pitch commits promptly with `actualLocation` null, nothing is held open, and provenance shows exactly when and by whom each location arrived. Coverage denominators (§12.4) simply rise as the gaps fill.
- **Between-pitch runner events:** the call screen (and every idle loop surface) carries a field affordance opening §15.6's idle field — steals, caught stealings, pickoffs, WP/PB advances — without disturbing any pitch in progress.
- **Batter-action chips:** a small optional row on the outcome step — `bunt` / `pulled` / `slap` / `fake` / `slash` — one tap when the batter showed something, untouched otherwise (absent = conventional posture). Also settable post-hoc from the pitch summary, since "wait, was she squared?" is a between-pitches realization. Sticky suggestion: if the previous pitch of the AB carried an action, the row pre-highlights it for quick repeat.
- **Fielding sequence entry:** the deepest sub-flow, specified in full in §15 (v0.43 grammar: trajectory first, ball path drawn or implied by the fielder drag, throw drags, Safe/Out runner resolution) — with every GameChanger-broken play as a test case (§14).
- **Dirt-band hinge (§3.3, composition in §11.4):** the zone canvas extends below the zone rect into a visually distinct dirt band — everything below **`y_ground` (§3.1)**, and only that. Ground drawn in front of the plate projects above the ground line and is scenery, not trigger (§11.4); the two regions are different shapes, and drawn ground spans the boundary. This boundary is derived, not tuned: above the ground line a pitch can still be in the air, below it a pitch cannot, so the physically meaningful line and the interaction trigger are the same line. The band is still a *visual* target (the coach aims at dirt, not at a number), but where the dirt starts is no longer a layout preference, and the golden tests assert its position rather than approving a look. A release inside that band hinges the canvas to a top-down plate/dirt plane sharing `ZoneCoord`'s lateral axis; a second tap there sets `bounceLocation`'s depth. The swap happens **on release, not on arm** — the entire press-drag-preview stays in the frontal plane, so the existing arm-low-drag-up-to-correct grammar keeps working (coordinate spaces never change mid-gesture); only a release landing in the dirt band triggers the hinge, and the second placement is its own independent gesture. Skipping the second placement and using the skip-location affordance (§11.2) records "in the dirt, depth unknown" — a `BounceCoord` carrying `x` and no `depth` (§3.3) — with no separate tap-vs-drag heuristic needed. In that plane the two controls narrow to match: Cancel becomes **Back to zone** (un-hinges, commits nothing) and skip becomes **Depth unknown**.

### 11.2 The Mode Ladder (degradation under pressure)

| Mode | Captures | When |
| --- | --- | --- |
| **Full** (default) | call + actual + outcome + batted ball detail | normal game flow |
| **Scorer** | actual + outcome (skip call — e.g., opponent at bat, or catcher calling her own game) | opponent half-innings, tempo spikes |
| **Bailout** | outcome only — one giant BALL / STRIKE / FOUL / IN-PLAY row (v0.41); STRIKE records `strike_unspecified` (§4.1) | chaos: conferences, injuries, arguments |

- Mode is *per-tap-sequence*, not a settings toggle: the actual-location canvas has a persistent "skip location" affordance, and a two-finger swipe drops to bailout for the current pitch. The ladder exists to protect the one invariant that matters: **the count and game state are never wrong.** Heat maps survive 15% missing locations; a scorebook that disagrees with the umpire kills the app's credibility permanently. The ladder degrades one operator's pitch; the duty split (§12.2) is the other axis entirely — at full capture depth two operators are the design center, and a solo operator attempting full capture should expect to live on this ladder.
- Opponent half-innings default to Scorer mode with the batted-ball flow emphasized (their spray data is the scouting payload) — no calling UI shown.

### 11.3 State the Loop Manages Automatically

Batter advance (from lineup projection), count reset, inning flip, pitcher's pitch count, forced advances on walks and HBP (v0.41: auto-generated **and auto-applied** — no confirmation; the forced chain is rulebook arithmetic with nothing to decide, and the realistic error, a mistapped outcome, is one confirm couldn't catch and undo does), courtesy-runner prompts when the pitcher/catcher reaches base (RuleSet-gated), and D3K arming (uncaught third strike with first base open / two outs → Diamond prompts the runner resolution instead of assuming the out). Undo is always one tap, top-level, **action-scoped** (v0.41): one tap voids the last *action*, meaning the last scorer-authored root event (a `PitchThrown`, a `CountCorrection`, a committed play) together with everything the loop auto-appended for it, so a bases-loaded walk reverses as one unit, not five. **Its depth is bounded at the plate appearance (v0.54):** a plate appearance **seals when the next one begins, and stays sealed**, and undo reaches anything unsealed. "Begins" is *calling the next pitch* — the first type tap — or, when the call is skipped, any action belonging to that pitch; the same signal that already dismisses the "record last pitch" offer, since starting the next call is what moving on looks like. Staying sealed is the load-bearing half: a floor defined as "the current plate appearance" bounds nothing, because peeling one empty moves the floor into the previous one and so on to the first pitch of the game. So the wall is a frozen point, not a recomputed one. The button **disables** when everything is sealed rather than declining silently. Undo is for taking back what you just did; reaching into a finished batter is an edit (§6), deliberately a different gesture.

**D3K arming is the scorer's, not the pitch's (v0.46).** The resolution is offered on **every third strike the batter was entitled to run on** — first base open, or two already out (`uncaughtThirdStrikeLive`, read from the state *before* the strikeout is folded, since with two away the strikeout is the third out and the answer flips). Nothing about the pitch gates it: a passed ball on a letter-high fastball lets her run exactly as a ball in the dirt does, and only the scorer knows which happened. Where the rules prevent her running at all the offer is **hidden**, not greyed — that is the one case with no judgment in it.

**It is declared with the pitch, not corrected after it.** A dropped third strike is the equivalent of a ball put in play: an outcome that opens a surface, not a note on a strikeout. So it lives on §11.1's outcome sheet beside **In play**, shown only at two strikes with the batter entitled to run, and labeled **Dropped 3rd strike** — the less precise word, because it is the one scorers use and already the wire word (§4.3). Choosing it asks which strike it was (called or swinging: the swing data matters most on exactly the pitches likeliest to have been offered at, so `strike_unspecified` would be a poor trade for one tap), then what happened to her. The automatic strikeout out is **never written**, so nothing is voided and no phantom out reaches the stream.

Four one-tap endings, plus the field for everything else. **Out at first** → `FielderTouch{2, fielded}` + `FielderTouch{3, received_throw}` + `RunnerOut{atBase: 1, how: strikeout_d3k_throw}`, putout to 3 and assist to 2 — credit the bare recorded strikeout never carried. **Out (tag)** → `FielderTouch{2, tag_applied}` + `RunnerOut{atBase: 1, how: tag}`. **Safe (wild pitch)** → `RunnerAdvance{0→1, dropped_third_strike}` alone. **Safe (passed ball)** → `FielderTouch{2, missed_catch}` anchored to the pitch, then the same advance linked via `enabledByTouchId`. The Safe pair is §13 working as designed — a passed ball is recorded as physics, a wild pitch is the absence of one, never a ruling. **Go to field** opens §15.6's surface with the batter walked up: a D3K is a pitch-anchored draft (v0.45) with a runner entitled to first, so play #5's throw into right field is entered with the ordinary play grammar and nothing D3K-specific.

---

### 11.4 Pitch Canvas Composition

The canvas is not a bare rectangle. Both planes are anchored by home plate, because the plate is what tells a coach at a glance what she is looking at, which way is inside, and where the dirt begins. Composition is specified here; §18.7's design language governs how it's drawn.

**Frontal plane (default view).** Catcher's perspective, matching the spatial arrangement coaches already know from broadcast K-zone graphics:

- **Home plate anchors the bottom**, drawn in perspective — 17″ edge toward the pitcher (up-screen), point toward the catcher (down-screen) — and foreshortened. Foreshortening is not applied as a ratio; it falls out of the pinhole ground projection specified below.
- **Lateral registration is exact, not decorative.** `ZoneCoord.x` is normalized against the fixed 17″ plate width (§3.3), so `x = ±1` must align with the plate's 17″ edge. The zone rect sits directly above the plate it describes; a pitch tapped at the zone's right edge is visibly over the plate's right edge. Note the consequence of perspective: because the plate's near side corners are ~8.5″ closer to the camera, they project slightly *wider* than `x = ±1`. Registration is asserted against the 17″ edge specifically, never against the plate's widest visible point.
- **Batter's boxes flank the plate** as outlines, both always drawn and neither filled or shaded (v0.36). The occupied side is shown by the batter silhouette below and by nothing else — two competing cues for one fact is worse than one. The canvas itself never mirrors, since `x` is absolute (§3.1): only the silhouette moves. At true scale the boxes run off-frame laterally; what must be on-canvas is the 6″ gap, the inner line, and the front corner (below).
- **The zone rect carries the call grid** when calling is on (§10.1's layout), and extends above and below it for out-of-zone airborne pitches — enough room that shin-high, ankle-high, and eye-level are comfortably distinguishable.
- **The 3×3 is always drawn; the surrounding sixteen are conditional (v0.38).** The strike zone and its nine cells render at all times, on the calling surface and the actual-location surface alike — they are the frame every location is read against, and a canvas without them has no scale. The sixteen cells around them are drawn **only while a pitch is being called, and only those the selected pitch can actually be called to** (§10.1's per-type callable set): they are the available *choices*, so they appear when there is a choice to make and go when there is not. On the actual-location surface they are not drawn at all. They remain **implied** — containment still resolves a pitch anywhere on or beyond the canvas into exactly one of them (§17.4), so nothing is lost by leaving them unpainted. Drawing all sixteen unconditionally fails twice over: it claims every location is available when most are not, and it spends ink on a surface whose whole job is to receive one tap.
- **A callable zone draws as one swatch the size of a strike-zone cell**, centered on its target (§10.1's nominal bounds) — never one mark per member cell. A grouped zone is a single call with a single code, so painting its cells separately shows several targets where there is one, and a layout with three grouped chase zones lights most of the canvas, which reads as "everything is available" and tells the coach nothing. The swatch is the indicator, not the hit region: the zone still owns everything its cells cover, so a tap far off the plate lands correctly even though the mark beside the plate is small.
- **The zone rect and the call grid stay orthographic.** Perspective belongs to the ground furniture — plate, dirt, boxes, catcher — and stops at the zone. `ZoneCoord` is a plain affine mapping and §10.1's `bounds` are rectangles in that space; perspective on the grid would make cells unequal tap targets and break tap-equals-coordinate.
- **The dirt band** is everything below `y_ground` (§3.1) — the hinge trigger (§11.1). Its top edge is derived; its depth below the ground line is a layout call, needing only to comfortably contain the foreshortened plate plus a tappable margin. It is *not* the same region as "where ground is drawn": ground in front of the plate projects **above** the ground line and is scenery, not trigger. See the ground rule below.

**Canvas geometry.** The frontal plane is a scale drawing. Values are in `ZoneCoord` units, quoted for the canonical 12U profile (§3.1); every one moves with the profile.

**The projection.** Ground furniture is drawn through a pinhole projection — camera at height `H`, horizontal distance `d` to the plate's 17″ far edge, azimuth 0 — anchored so that ground at `u = d` maps to `y_ground`. Everything else follows:

| Quantity | Formula | Value at H = 4 ft, d = 20 ft |
| --- | --- | --- |
| Plate on-screen depth ÷ width | `H / (d − 17″)` | **0.215** |
| Near-corner splay | `d / (d − 8.5″)` | 3.7% |
| Horizon | `y_ground + H / zoneHeight` | y = +1.354 |
| Ground at distance `u` | `y_horizon − (y_horizon − y_ground)·d / u` | — |

`d − 17″` is the plate's near point, which is closer to the camera than the 17″ edge `d` measures to.

**Azimuth 0 is a constraint, not an incidental parameter.** An off-axis camera projects the 17″ edge's two corners at different distances from center, so `x = ±1` no longer maps symmetrically onto it and the exact-registration requirement above breaks. That is why the plate renders as a symmetric trapezoid with no tilt, even though broadcast reference footage is shot off-axis. Whether the ground furniture should tilt per batter handedness is Open Question #9.

Two further constraints apply, and they are **coupled** — satisfying one does not satisfy the other:

- **Ratio band 0.15–0.25** ⇒ `0.15 (d − 17″) ≤ H ≤ 0.25 (d − 17″)`. At H = 4 ft this is d ∈ [17.4 ft, 28.1 ft].
- **Splay ≤ 5%** ⇒ d ≥ 14.9 ft.

At H = 4 ft the ratio band binds first: d = 15 ft is not a legal camera despite satisfying the splay rule, rendering at 0.294. Anything selecting a camera, including test fixtures, checks both.

**Anchoring puts the plate's front edge on `y_ground`**, and that identity holds independently of `H` and `d`.

| Canvas quantity | Value | Derivation |
| --- | --- | --- |
| Axis scale ratio | **0.354** at 12U | `8.5″ / zoneHeight`; per-profile, never a literal (§3.1) |
| Ground line `y_ground` | **−0.646** | §3.1's canonical inputs |
| Plate on-screen depth | 0.152 y-units | 0.215 × (17″ / 24″) |
| Plate point at | y = −0.798 | `y_ground` − plate depth |
| Lateral range | **x ∈ [−4.0, +4.0]** | contains where the batter stands (x ≈ 2.4–4.3 at 12U), not merely the chalk |
| Vertical range | **y ∈ [−1.05, +1.50]** | ½ zone height above the zone; dirt margin below the plate point |
| Resulting canvas | ≈ 68″ × 61″, **≈ 1.11 : 1** | slightly landscape; the call grid is drawn *on* this canvas (v0.38), so the rest of the tablet carries the screen's furniture instead |

**Ground is bounded by contrast, not by extent.** Ground in front of the plate projects upward and compresses: at the default camera, 1 ft in front reaches y = −0.55, 2 ft reaches −0.46, 5 ft reaches −0.25. It is drawn to its natural extent — the region in front of the plate is where a bounced pitch physically lands, and it renders as dirt — and **fades with distance**, reaching neutral before it sits behind the zone rect. What §18.7 protects is grid legibility against a busy backdrop; a fade satisfies that without truncating the ground furniture drawn on it. Fade endpoints are a fidelity call, tuned with the two treatments below.

Drawn ground therefore spans the ground line, and **the trigger region is not identified by looking like dirt.** The landmark for the boundary is the plate's 17″ front edge, which by construction lies exactly on it, reinforced by the tonal step where the fade meets full-tone ground. That step is inherent in the fade and is *not* drawn as a rule across the canvas — an explicit full-width line reads as an arbitrary graphic, and the boundary is legible without it. Re-check that judgement when the hinge lands, since that is when the boundary starts carrying interaction weight. Everything drawn above the line renders behind the marker layer.

**The top stops where information stops.** +1.5 is half a zone height above the zone — ≈ 12″ over the letters, upper-face level at 12U. Higher than that carries nothing for scouting or development: a foot over the head and two inches over the head are the same observation, and §17.4 buckets both as uncompetitive-high. Such pitches stay recordable, just unresolved, landing on the top edge. Shoulder height (y ≈ 1.31) stays resolved, since an elevated fastball is a location rather than a miss. Trimming here buys vertical room for the count HUD and outcome row — see the note below on which dimension binds.

**The lateral range contains where the batter stands.** Reaching the chalk is not the requirement; a pitch may be recorded anywhere on the canvas, including at the batter, and the silhouette (below) simply lays over part of it. A 12U stance puts her body center ≈ 26–30″ off plate center — x ≈ 3.1–3.5, spanning roughly x ∈ [2.4, 4.3] — so ±4.0 leaves capture room on both sides of her. What this spends is horizontal room, which competes with the rest of the screen; that is why it stops at ±4.0 and not ±6.0, where the entire 36″ box would fit but its outer ~20″ is chalk nobody stands in. The range also has to contain the ring cells of §10.1's call grid, which it does with room to spare — the ring's nominal targets sit at x ≈ ±1.33.

**What the frame costs depends on which dimension binds, and the two extents are not interchangeable.** The zone's on-screen size is set by the binding dimension alone:

- **Height-bound** (canvas given the full screen height): zone px = `panelHeight / verticalExtent`. Lateral range does not enter, so widening is free and trimming the top *enlarges* the zone.
- **Width-bound** (canvas given a width budget so a call column fits): zone px = `panelWidth × 2 / lateralExtent`, scaled by 17″/24″ for height. Vertical extent does not enter, so trimming the top is free and widening is what costs.

Worked at 1180 × 760 usable, leaving ~450 for the call column: ±4.0 with the top at +1.5 gives a 730 × 657 panel and a 182 × 258 zone. The earlier ±1.9 / +1.80 frame gave 189 × 267 — so reaching the batter and the full box cost ~4% of zone size and ~400 px of width, not tap precision. Do not generalise either bullet into "widening is free"; check which dimension binds first.

**The ground plane above the line is invertible, and is deliberately not used that way.** `u = k / (y_horizon − y)` recovers a distance from any tap on drawn ground, so a tap 4 ft in front of the plate does correspond to a real bounce depth. It is not read as one: the same pixel is also a legitimate airborne location (y = −0.40 is both ground 2.8 ft out and a pitch 5.9″ off the dirt at the plate), and the airborne reading is overwhelmingly the common case. Taps above `y_ground` are airborne; bounce depth is captured only through the hinge and the top-down plane (§3.3, §11.1).

At the default camera the horizon sits at y = +1.354 — inside the canvas, above the zone rect. The fade reaches neutral well below it; no horizon is drawn.

The ground plane's projection is **not** isotropic with the frontal plane above it. The two planes share the lateral axis and nothing else (§3.3): depth comes only from the top-down plane after the hinge, and nothing infers a depth from where a tap landed inside the frontal plane's dirt band.

**Batter's box dimensions are a `RuleSet` concern**, like zone dimensions (§3.1) — never an `if (softball)` branch:

| | Box | Offset from plate | Fore/aft of plate center |
| --- | --- | --- | --- |
| Fastpitch softball | 36″ × 84″ | 6″ | 48″ / 36″ |

Chalk is **3″** wide and the rulebook's 6″ is measured to its **inner (plate-side) edge**, so at the plate's depth the inner line spans x ∈ [1.706, 2.059] — both edges comfortably on-canvas at ±4.0, so the band reads as a line rather than clipping into a wedge.

**The inner and front lines render; the back and outer lines do not.** The inner line and the front line are what a coach reads position against; the back line toward the catcher and the outer line toward the dugout carry no locating information and run off-frame at true scale. Chalk is clipped only by the box's own extent and the canvas edge, and fades with the ground it is painted on.

At the default camera the inner line is laterally on-canvas from `u ≈ 0.426 d` — nearer than the box's own back line, so nothing clips laterally and the near end is instead bounded by the canvas bottom at `u ≈ 199.7″`. The visible run is therefore **≈ 80″ of an 84″ box**, y ∈ [−1.05, −0.363], turning a corner into ≈ 25″ of the 36″ front line before leaving frame. Each box reads as a box receding out of view, as in the reference K-zone, where the boxes are frame-cut the same way.

**Top-down plane (after the hinge).** Deliberately unmistakable at a glance — if the two views could be confused, the hinge design fails:

- **Plate from directly above**, true pentagon, no perspective; the 17″ edge is the `depth = 0` line and the hinge seam.
- **True scale, and the same px-per-x as the frontal plane.** The plate is literally the same width in both views, which is the strongest available cue that the planes register.
- **The depth range is derived from those two constraints, not chosen.** Sharing px-per-x fixes px-per-inch; isotropy then makes the drawing rect's shape fix how many inches fit vertically. Both planes occupy the same rect, so the top-down plane covers exactly the frontal plane's own vertical extent in inches — `verticalExtent × zoneHeight` = **61.2″ = 5.10 ft** at 12U. (An earlier draft quoted −1 ft…+5 ft, 72″, at ≈ 0.94 : 1; that assumed a taller rect than the frontal plane actually occupies and was never achievable alongside px-per-x parity. Corrected in v0.35.) Note the range moves with the batter's zone height, since the rect's aspect does — the rect is the same rect, only what fills it changes.
- **Only the anchor is free**, and it splits the range at **−2.5 ft … +2.60 ft**. The aft extent is fixed at 30″ *in inches*, not as a fraction: it holds the plate's whole 17″ pentagon plus 13″ of catcher-side room, and the plate is 17″ for every batter (§3.3), so the profile-dependent part is absorbed by the fore side instead. A short hop landing just behind the front edge is a common bounce, not an edge case — it is why `depth`'s sign convention exists.
- **Depth grows up-screen** toward the pitcher, matching the frontal plane's sense of "away from the catcher." Negative depth — a short hop between the plate and the catcher, or a ball skipped past the back edge — extends below the plate toward her. Bounces past either end land unresolved on the edge, the same treatment the frontal plane's +1.5 top gives an eye-level pitch.
- **The plate's point is what tells you which way is front**, in both planes and with no label, ruler or line weight doing the work. Both views are the catcher's: we are behind home looking out at the field, and the plate's point aims back at us. That is why the top-down plane needs no catcher drawn, no signed depth labels, and no emphasis on the `depth = 0` line — the plate has already said it, more legibly than any of them could. The `depth = 0` gridline is therefore drawn exactly like every other gridline.
- **A foot ruler, not bands.** Earlier drafts labeled 0–2 ft / 2–4 ft / 4 ft+; those assumed the un-achievable range above, and `depth` is a continuous float that is never bucketed in storage anyway (§3.3). A gridline every foot describes the axis with less ink and no invented thresholds. Labels are unsigned ("1 ft", "2 ft") on both sides: the plate sits between them, so which side runs toward the catcher is not something a label has to carry.
- **Batter's boxes flank the plate**, unshaded as in the frontal plane, and the lateral axis stays in register with the frontal plane above it. **Inner and front lines render; back and outer do not** — the same rule the frontal plane follows, and whether the front line is *visible* falls out of `RuleSet` rather than being special-cased: fastpitch's box runs 4.0 ft out front and off the top of this canvas, so the front line is simply not drawn, while a shallower box would terminate in view and close itself. No catcher is drawn (v0.35): there is no rulebook position for one, so any mark would be invented, and nothing needs one to say which way is behind — see the orientation note below.

**Controls live outside the canvas.** Cancel, skip-location, and any mode affordance must sit in a strip outside the drawing area, not overlaid on it. Overlaid on the dirt band they occupy the hinge trigger region — a live hit-target conflict, not a cosmetic one — and the problem compounds after the hinge, since the same controls have to exist in the top-down plane where the dirt is the entire canvas.

**Fidelity is an open question, settled by field test — not by argument.** The composition matches a broadcast K-zone; how richly it should be *rendered* is genuinely contested and both positions have merit:

- **For richness:** visual craft signals a serious product. A canvas that looks thrown together undermines trust in everything behind it, and "serviceable" is the failure bar (§18.7). Broadcast and video-game K-zones look authoritative for a reason.
- **For restraint:** the entry canvas is used ~120 times a game, in sunlight, on a clock. Every decorated pixel competes with the tap markers and grid that carry the actual information.

The likely resolution, to be validated rather than assumed: a **dimensional, materially real plate and dirt** — chalk with weight, texture, honest shading — on a **neutral background**, since the contrast cost lives in a busy backdrop behind the grid, not in the plate in front of it. Note also that what reads as "serious" in a reference image is mostly *precision* — correct plate perspective, confident proportions, exact lateral registration (above) — not photographic detail; craft and busyness are separable. The geometry table above is not part of the fidelity question: it applies identically to both treatments, and getting it right is most of what makes either look intentional.

**The shadow batter is paint, never a hit target.** Wherever it ships, it renders behind the marker layer and takes no pointer events: a pitch may be recorded anywhere on the canvas, including at the batter's body, so a silhouette that swallowed taps would make the region it occupies uncapturable — the opposite of why the lateral range was widened to contain her.

**The batter silhouette is built and derived from the batter's zone (v0.36), and is off by default.** It is a location cue — a coach picks a call and reads an actual against a body, not against an empty rectangle — and a calibration instrument besides, since the zone rect visibly spanning knee to armpit is a proof no table can give. Earlier drafts kept it off the entry canvas on the grounds that `y ∈ [0,1]` is *this batter's* zone and a fixed-size silhouette is honest only for a batter of the height it was drawn at. That objection is answered rather than overridden: the silhouette is **derived from the zone profile**, with the knee at `y = 0` and the armpit at `y = 1` — definitionally the zone's own edges — so it tracks the rect for every batter by construction and cannot drift from it. Stature follows from the profile (58″ at 12U), and everything else is human proportion expressed as a fraction of it. It renders in the **frontal plane only**: its job is the vertical read, which the top-down plane has no axis for. The head is frame-cut by the +1.5 top at upper-face level, which is that trim working as designed. **What is not yet good enough is the drawing** — the figure is built from uniform-width strokes and does not read convincingly as a batter — so it is hidden pending DIA-013, and the entry canvas carries no occupied-side cue in the meantime. Visibility is a parameter rather than a constant, because a future practice state (bullpens with no batter in the box) wants the same switch driven by a user setting.

**Fidelity is per-surface.** Review and scouting screens (§18) are used at leisure, indoors, with markers already placed — full richness is right there and is where a coach forms their impression of the product. The entry canvas is the one surface where decoration competes with a job. Build both fidelities of the entry canvas behind the same coordinate mapping and compare them on a real tablet in daylight (DIA-011 golden tests).

---


### 13.6 Sacrifices (v0.43)

The two sacrifices need opposite treatment, because only one of them is visible in the physical record.

- **The sacrifice fly derives.** Any ball caught in the air by anyone — fly, pop-up, or line drive, including one deflected first and caught by somebody else (v0.57) — with fewer than two outs, the batter retired, and a runner scoring on the batted ball. Every condition is in the stream already, so the scorer enters nothing. **The error condition is about the run, not the play (v0.57):** a run that needed a misplay was not bought by her out — her leg links to it and is recorded as `error`, so it does not count — but an error elsewhere on the play does not cancel the sacrifice. A runner tags and scores, the throw home gets away, another runner takes a base: still a sacrifice fly, and still an error. **The dropped fly is the exception, and is asked (v0.57).** The rule's second clause credits a sac fly when the fly is *dropped* and a runner scores who, in the scorer's judgment, would have scored had it been caught — judgment, so the record cannot settle it. It is asked only when the touch that ended the ball's flight was a drop: a fly that falls in clean is a hit, and a run scored on a hit is never a sacrifice.
- **The sacrifice bunt cannot derive, so it is asked.** Nothing physical separates bunting to move the runner from bunting for a hit — the difference is entirely intent, which is why it is the one judgment §13 stores as a flag — the only one, since v0.56 deleted `ordinaryEffort`. It is stored on the batted ball (`BallInPlay.sacrifice`), and asked exactly when the question is live: a bunt — on the ground or in the air (v0.58) — that moved a runner up.

An explicit `sacrifice` flag overrides the derivation in both directions, so a scorer can deny a sac fly the projection inferred, or claim one it missed — **except with two out (v0.57)**, when neither sacrifice exists by rule: her out ends the inning, so she gave nothing up to move anyone. The derivation checks the outs at contact before it reads the flag, so no stored judgment can claim one, and the ✓ never asks then. Both sacrifices are plate appearances and neither is an at-bat.

**Both questions are asked at the ✓ (v0.57)**, after §13.2's reach question and before the commit: *Sacrifice bunt?* or *Sacrifice fly?*, yes or no, named for the play. Not on a standing chip — §15.3 already keeps baserunning judgments off standing buttons, and the old chip read "Sacrifice bunt" on a dropped fly — and not on the runner either, although the judgment is about what her advance was worth: the runner it turns on is usually the walk-up nobody touched (§15.1), so a question attached to her would go unasked on the ordinary sacrifice. One place, reached however the play was entered. The cost is one tap on the plays that raise it, the same trade §13.2's reach question already makes.

**Catcher's interference (v0.43)** is one of two official errors charged with no misplay touch behind it: an `outcome: catcher_interference` award derives **E2 by rule** — kind `interference`, anchored to the ⚖ the loop emits with the award. Hit rank is likewise refined in v0.43: a batter leg with *any* enabler (a clean throw included) or a non-batted reason never raises the hit base — "took second on the throw" is a single plus an advance, not a double.

**Mental errors** (threw to the wrong base, held the ball too long) are officially not errors and Diamond doesn't pretend otherwise — but they're exactly what `ScorerNote` tags are for (`wrong_base`, `late_decision`), and the development projection surfaces them alongside physical misplays.


## 15. Field Entry UI — Drag, Throw, Modify

The interaction model keeps what GC got right — dragging the ball around the field *is* the natural grammar for a play — and fixes the part that's broken: there was never a place to say "and something else happened right here."

### 15.1 The Canvas (v0.43)

The play canvas shows the field with fielders at their positions. Entry order is fixed and load-bearing: **the trajectory comes first** — `ground` / `line` / `fly` / `popup` / `bunt`, where *Bunt* opens a second pair, *on the ground* (`bunt`) or *in the air* (`bunt_air`), because a bunt still has to say whether it can be caught (v0.58); when the outcome sheet already said Bunt, the field skips the five and asks only that pair — asked in a centered modal that opens with the surface (every popup on this surface is a centered dialog, sized to its content) — because the batted-ball type drives every later option: the what-happened popup's contents, the caught-vs-fielded readings, the fly-out inference. Until it's answered, any canvas touch just brings the question back.

**The batter runs on contact.** The surface opens with the batter-runner already walked up to first (the forced cascade applied — runners never pass each other), because a ball in play means she's running. Presumed movement **renders in motion — a third of the way up the line** — never parked on the next base: the canvas shows runners running, and the difference between "she's going there" and "she got there" stays visible until the scorer answers. A resolved runner stands on her base. The presumption resolves, never lingers: a **caught first touch** voids it — the unattributed walk-up comes off and the batter is out in the air, putout to the catch; an **out marked at the base a runner's last leg reached** absorbs that leg into the out (no phantom advance ever commits); and **a misplay raises the hit-vs-error question rather than answering it** (v0.56): the presumed reach stays unattributed until the scorer says how far the batter earned. She is asked in the one place she has not already answered — the SAFE popup when the batter is dragged past first, the force play's SAFE pill when a throw settles her at first, and the ✓ when nobody touched her at all. Only the reach is ever in question; every base beyond it was answered by its own popup when she was dragged there.

**The scorer names the error, and the answers are one chip per misplay she could charge it to** — *on the fielding error*, *on the throwing error* — rather than a single *on an error* the engine then attributes for her. This is the last guess in hit-vs-error, and it is not a guess that can be made well: *boot, recover, throw it away* and *field it clean, throw it away* put the batter on first off different mistakes, and a rule reading the **first** misplay charges the boot on the first play while a rule reading the **latest** charges the throw on a play where the boot is what beat her. The physical records are the same; only the scorer knows. So she says. The kind comes from §13.2's own mapping, which is what stops a chip naming one error while the box score charges another, and the fielder is named only when two of a kind would read alike.

**The breakdown is its own dialog**, opened by the error answer rather than sitting beside it: at third the ways three bases can divide are *double and an error*, *single, 2 base error*, and — where one misplay gave all three — *3 base error*, and offering those inline would make a four-chip row a seven-chip menu. It is asked whether or not the reach is still open, since dividing the bases is a question either way, and it stops at the base she is already standing on: once she has been credited the single, *she earned none of it* is an answer contradicting one she has given. It is also the **batter's** question alone — it divides bases between a hit and an error, and a runner already aboard has no hit to divide, so her advance links whole. Where **two** misplays are in play, earning nothing says nothing about the reach, since first may well have come from the other one; the chip reads *none of it earned* and the ✓ asks who put her on. That is play #2 exactly: the boot gave first, the throw gave second and third, and the play reads as two errors rather than one of three bases. Claiming the reach automatically was wrong in both directions. It destroyed the clean single that a later boot only added to, and it could not be taken back, because the chain offered re-attribution to another touch but no way to *clear* a link — and on a one-touch play there was nothing else to point at.

**The ball's location, two ways — drawn or implied:**

- **Draw the path (two taps):** first tap = where the ball first hit ground, wall, or glove (`landing`, the spray-chart point); second tap = where it ended up (`retrieved`). The path renders as an accent streak with live distances ("128 ft → 152 ft"). Routine balls skip the second tap — the next action simply proceeds and `retrieved` stays absent; a later open-field tap adjusts the streak's end. A landing on the fence spline auto-suggests `offWall`.
- **Fielder's choice is the batter's answer alone (v0.56).** Mark: it is how the batter reaches first when the defense elects to throw somewhere other than first, so it is never an answer about a runner already aboard — and at the plate it was nonsense. It comes off the SAFE menu entirely and lives on the batter's reach question, where **an out on a runner the batter's contact pushed decides it without asking**: a runner retired at the base she started from, or one beyond it, *is* the defense choosing her over the batter. Two bases is a different play — first to third on a ball through the infield is a runner going on her own, and the batter standing on first got there on the hit — so that one is asked. Wherever **anybody threw**, *fielder's choice* joins *single* as an offered answer — any throw, not one demonstrably taken away from first. Where the throw was going is not recorded, and marking a throw wild deletes the reception that used to imply it, so keying on that made the answer set depend on whether a different answer had eaten its own evidence: bases loaded, grounder to short, throw home and away, and the menu offered *single* alone. The test is the scorer's in any case — a single if there was no play to be made, a fielder's choice if they could have retired somebody elsewhere — which is a judgment rather than something the record settles.

- **The reach question runs on every play and usually costs nothing (v0.56).** It asks whenever the batter is still standing on her walk-up and was not retired, and it collapses when only one answer is possible — a clean single applies itself. The scorer is asked exactly when the record leaves the answer open: a misplay to charge, a throw that could have gone bad, a defensive play elsewhere.

- **Every way of settling a runner asks the same question (v0.56).** The force play's pill, a drag to a new base, and a drop on the base she is already standing on are three gestures for one event, and the last two were silent. The third is not an edge case: the walk-up already displays every forced runner at her next base, so dropping her where she stands *is* the ordinary gesture. Settling the batter that way also nulled her presumed reach, leaving the ✓ nothing to ask, so a whole play could commit without a single question. Answering SAFE settles *why* she is safe, not only that she is.

- **A runner's plain answer is *on the play* (v0.56).** She was offered *on the hit* and *on the throw*, which are the same answer for her: linking her leg to a clean throw changes no ruling, because the enabler only caps **hit rank**, and hit rank is the batter's affair. *On the throw* stays on the batter's menu, where it is the difference between a double and a single plus an advance. Two of its answers **write** the misplay they name rather than pointing at one that exists: *the throw was wild* retypes the thrower and takes the reception off (nobody receives a wild throw), *dropped the throw* retypes the reception, and both link her advance to what they wrote — §13.2's pair, the shape §15.6's passed-ball chip already uses. Without them a clean chain had no way to say a throw went bad, since the error answers only offer misplays already recorded.

- **Play the fielder (drag + popup):** drag the fielder to where she made the play — wherever she is dropped is where the ball went. Her release point becomes the assumed `landing` (when no path was drawn) *and* the touch's own `location` (§4.2); she renders at that spot for the rest of the play (render-only — per-play repositioning is not §16.4 alignment data). A **what-happened popup** then disambiguates, options driven by the trajectory: in the air — *caught / dropped / missed it / fielded*; on the ground — *fielded / booted / deflected / missed it*, where **deflected** is the ball that hit her and caromed away with no play to be made: a physical fact §13.2 never charges, and the ball stays loose. **Deflected is infield-only (v0.56)** — Mark: *"outfielders can't deflect, they can only miss"*; a ball off an outfielder is a play she did not make, not a carom another fielder is standing there to take. And it is *fielded*, not "picked it up", wherever the ball is still a batted ball: you field a batted ball and pick up a **loose** one, which is why §15.6's between-pitch popup keeps the other word.

**A boot or a drop leaves the ball at her feet (v0.56)**, so she is shown holding it and the next fielder tapped is receiving a throw. Mark: *"when we boot a ball, we don't pick it up"* — the scorer should not have to say she did, so the recovery touch is **minted** at the moment a throw proves she had it, exactly as §15.6 already mints one for the seeded catcher. The committed chain is unchanged; one dialog disappears. `missed_catch` and `wild_throw` are not treated this way: there the ball is genuinely past somebody.

**Possession is Diamond's belief, and one tap corrects it.** Tapping the fielder shown holding the ball says she does not have it; the ball goes loose and the next fielder tapped is making a play on it. That is how a boot caroming to somebody else is entered, and it is the same gesture §15.6 always had for the seeded catcher — before v0.56 it cleared only that seed, so it silently did nothing whenever possession had been inferred from a touch. **"Missed it" records no touch at all**: she ran there and never touched the ball, which is officially nothing (§13 — no touch, no chargeable anything) beyond where the ball went. A **tap** on a fielder is the zero-distance drag: she played it where she stands.

**The rest of the play:**

- **A throw is one tap.** While the ball is held (the holder wears the accent ring), tapping any other fielder throws to her — `received_throw` at her spot; dragging her instead places the reception where she's dropped. After a drop, a boot, or a throw away the ball is *loose*: the next fielder interaction is a play on the ball (the what-happened popup), never a reception. The ball's whole route — off the bat, then touch to touch — draws as dashed accent segments, so every tap visibly moves the ball from one spot to the next. **A throw arriving at a base with a runner provisionally heading there pops the SAFE/OUT pair at that bag** — the force play is the question, asked where it happened; one tap resolves it (OUT absorbs the walk-up into the putout; SAFE stands, and §15.4.2's prompt takes it from there if the throw beat her). The pair never appears from a runner tap alone: runner-resolution targets require an actual drag, or a throw that puts the question.
- **Drag a runner** toward a base and two targets appear at that base — **SAFE** and **OUT** (the GameChanger interaction, kept because it was right); release on one, and a classified popup says what happened. The pair **stacks** — SAFE on top, OUT beneath — so two targets never sit side by side under one thumb: just off the bag in foul ground beside first and third, straddling the bag at second (safe toward the outfield) and at home (safe toward the mound, out behind the plate). Whichever pill the runner is over **lights up** as she is dragged onto it, and it is the same one the release resolves to — the answer is nearest-wins, so the midline between the two is the boundary and the canvas never shows one call while committing another. The vocabularies are disjoint by rule: a runner can only be *safe* on obstruction and only *out* on interference, so **SAFE** offers only what could actually have moved her: *the hit itself* (Single/Double/Triple/Home run for the batter — the only option that raises hit rank — "On the hit" for runners, or **"Tagged up"** once the ball has been caught, since nothing was hit anywhere she could run on) / *On the throw*, offered only when somebody actually threw / *On an error*, only when a misplay exists to link / *Fielder's choice*, gone once the batter is out in the air. **When exactly one answer is possible the surface does not ask** — a runner tagging home on a routine fly costs the gesture that moved her and nothing more. Meanwhile **OUT** likewise offers only the outs that were physically possible, likeliest first — a **force** needs the runner headed for the very next base *and* the chain of occupied bases behind her (a runner from second with first empty is forced nowhere: thrown out at home, she was tagged), a **catch removes every force** since nobody is compelled to advance once the batter is out in the air, **fly out** is the batter's alone, and **Didn't tag up** (§4.3's `appeal`, putout to whoever holds the ball at the bag) is a runner's alone and only against a catch — plus *Interference* (⚖ + `how: interference`). **At three outs the OUT half of every pill goes away** (§4.4): the fold flags `halfEnded` and the surface stops offering outs, so a fourth can't be recorded — which is also why the appeal disappears with two away, since the catch itself was the third out. The base itself reads as safe, and releasing a runner on the base she already occupies is an affirmation rather than a move: she settles there, with no `from == to` leg minted (§4.3 reserves that shape for surviving a rundown). Automatic movement — the walk-up, cascade pushes — never asks.
- Runner advance arrows still re-attribute from the chain (§13.4) when the popup's answer needs correcting.

### 15.2 The Play Chain Strip

As the sequence builds, a horizontal strip above the canvas renders it as nodes: **⚾ → 6 → 4 → 3**, with runner consequences hanging beneath the touch that caused them. This strip is the play's visible event log — and every node is a live control.

### 15.3 The Modifier Chip — "something else happened here"

Every node in the chain carries a small **"+" chip**. Tapping it opens a compact radial/sheet menu scoped to what makes sense *at that point in the sequence*:

- **On a touch node:** the misplay set — `dropped`, `booted`, `bobbled`, `wild_throw` (converts the following drag's meaning), `missed_catch`, `tag_missed`. A **receiving** node also offers *"the throw was wild"*, which retypes the **thrower** — the throw arrives badly, so the finger goes to the node that just appeared, while the charge belongs to whoever authored it — and **takes the reception off (v0.56)**: nobody receives a wild throw, and leaving the node committed a `received_throw` by a fielder who never touched the ball. A throw she *did* catch after a scramble is a `received_throw` with arrival quality `wide`, which the same sheet records. On a **receiving** node (`received_throw` and friends), the same chip also offers throw-arrival quality: `short hop` / `high` / `wide` — one tap, recorded as `receivedQuality`, zero effect on official scoring. Selecting a misplay recolors the node (misplays render amber; non-clean arrivals render with a subtle underline, not amber — they're information, not fault); a misplay that left the batter's reach unresolved raises §13.2's question — which error, and how much she earned — wherever she is next settled, at the ✓ if nowhere else.
- **On a runner consequence (v0.43):** the `RuleCall` set — obstruction, interference variants, ground rule, dead-ball award. These are baserunning facts, so they live on the runner-consequence chips' menus — never on a standing button, and **never among the first-pass SAFE/OUT answers either**: a call this rare offered on every play is noise, so it is found where it is looked for. Selecting one inserts a call node (rendered ⚖) into the chain just before that consequence, links it (an advance re-attributes to the call; an out's `how` becomes `interference`), and asks which fielder it was against, since obstruction is charged to her (§13.2).
- **On the ball's landing node:** infield fly, fair/foul dispute → `umpire_reversal`, spectator interference.

One mechanic, uniformly placed, covering errors *and* the weird stuff — no modes, no menu maze. The common case costs zero extra taps; the exceptional case costs exactly one tap plus one selection, at the exact spot in the play where it happened.

### 15.4 When the Misplay Gets Entered — Three Moments

1. **In the moment:** tap the chip mid-sequence as described. Fastest when the scorer saw it clearly.
2. **Prompted:** Diamond notices when the physics genuinely don't add up and asks — as a single dismissible chip suggestion, never a blocking dialog. The bar is *contradiction*, not suspicion. **The first-base variant is withdrawn in v0.43**: "the throw arrived and she's safe" is not a contradiction, it is an infield single, and Diamond has no timing model that can tell one from the other — asking would mean guessing at a misplay on every bang-bang play, and worse, asking it against the batter-runner's *presumed* advance (§15.1's walk-up), which is not a ruling the scorer ever made. A misplay stays one tap away on the node that took the throw. Chain ends at a fielder with no out and no advance-attribution → "bobble?" remains the shape of a real prompt: there, the record is genuinely incomplete.

**v0.56 keeps the withdrawal and drops its consolation.** v0.43 answered the first-base case with *"a misplay stays one tap away on the node that took the throw"*, and in the field that tap was not found: the SAFE pill settled the runner silently, so a throw that went bad could only be said from the chain strip, and a scorer who did not know to go there got an earned run and no error with nothing on screen to say a question had gone unasked (Mark, 2026-09-04, bases loaded, throw home). So **the SAFE answer now carries the vocabulary** — *the throw was wild*, *dropped the throw* — offered wherever the scorer settles a runner, on the pill as on the drag. Diamond still volunteers nothing: the routine answer leads, and offering an answer is not guessing at one. What is withdrawn is the *prompt*, not the words.

**v0.56 draws the line precisely.** Diamond still never asks *whether* there was a misplay — that is the withdrawn first-base variant, and it would be guessing. It does ask what a misplay **the scorer already entered** cost, which is not suspicion but an unanswered question about evidence she put on the chain herself. That one blocks at the ✓ rather than suggesting, because committing it unanswered would guess in exactly the way §11.2 forbids.
3. **Post-hoc:** every committed play stays editable from the play summary strip (and the audit view). Long-press → the same canvas + chain reopens. This is where hit-vs-error judgments get revised between innings or after the game — by re-attributing the advance, not by flipping a flag (v0.56) — emitting correction events (§6) with full provenance.

The design bet: moments 2 and 3 carry most of the load. **v0.56 moves hit-vs-error off that bet**: it is asked once, at entry, where the scorer already holds the opinion, and moment 3 revises it rather than settling it for the first time. In-game, the scorer's job is drags and taps that mirror what her eyes saw; adjudication is deferrable by construction, because the physical record is complete without it.

### 15.5 Commit & Undo

Nothing enters the event stream until the play is committed (tap the ✓ when the chain matches reality, or auto-commit when the next pitch's call screen is invoked with a consistent base/out state). **The play surface carries only that ✓ (v0.54).** Undo and cancel are one pair in the top bar, on every screen — the field had grown its own ↺ and ✕ while a third undo sat above them, so "which undo am I pressing?" was a real question, and the top one silently reached *past* the surface: tapping it with a play open voided the pitch underneath and left the draft anchored to an event that no longer existed, with nothing on screen changing. On the field the top bar's ↺ is the **play's** undo: it steps back one entry at a time (snapshots of the immutable draft, so there is no inverse operation per action), and when there is nothing left to step through — the trajectory question, nothing entered — it takes the play off the screen and the pitch with it, landing on the location canvas with the pitch still placed. Undo means the same thing at every depth: *take back the last thing I did*. **Cancel starts the play over in place**: the entries go, the field stays up, and the trajectory question comes back to the front. So ✕ means "I got this play wrong, let me redo it" rather than "throw the pitch away too" — and it can no longer strand a pitch, since an `in_play` pitch is never left with no play recorded. Leaving the field is undo's job, and undo takes the pitch with it. A between-pitch entry (§15.6) has no first question to return to, so there cancel is what it always was: close the field, recording nothing. Commit emits the whole event sequence atomically — `BallInPlay`, touches, calls, runner events — so undo (§6) of a play voids it as a unit, and a half-entered play never corrupts game state on a crash or a dead battery: uncommitted canvas state is journaled locally and restored on relaunch.

### 15.6 The Idle Field — Between-Pitch Runner Events (v0.42)

The field canvas is not only a batted-ball surface. A field affordance on the call screen (and every idle loop surface) opens the same canvas with **no ball in play**: defense at their current spots, runners at their bases, count HUD still up. Two jobs live here:

- **Seeing the field.** The coach can look at the defense and the base state any time. Alignment drag (§16.4) will land on exactly this surface when it ships (M2); until then fielders render at profile-scaled standard spots.
- **Between-pitch runner events.** Drag a runner to a base → `RunnerAdvance`, reason from a chip row: `stolen_base` (default, pre-selected), `wild_pitch`, `passed_ball`, `defensive_indifference`, plus `on an error` when a misplay is there to point at. Drag a runner to the out affordance at a base → `RunnerOut`: `caught_stealing` (default), `picked_off`, `tag`. **This is a play draft with a different anchor (v0.45)** — a play hangs its chain off the `BallInPlay` it mints, a between-pitch entry hangs it off the pitch that already exists — so the chain strip, every §15.3 chip, and §15.5's ✓ all apply here unchanged. That is the point: a caught stealing where a missed tag makes the runner safe is entered exactly the way a batted ball with an error on it is, and official scoring reads one shape rather than two. The catcher holds the ball by seed (true after every pitch); tapping her says the pitch got past her, and the next fielder is then making a play on a loose ball rather than receiving a throw (§15.1).

Two consistency rules carry over from the rest of the spec:

- **The Safe pair (§13.2, §11.3):** `passed_ball` is physics, never a ruling — the chip emits `FielderTouch{2, missed_catch}` anchored to the most recent pitch plus the advance linked via `enabledByTouchId`; `wild_pitch` is the advance alone. A second runner advancing in the same between-pitch window on the same passed ball links to the already-emitted touch — one PB, one touch, N advances.
- **Undo (§11.3):** each between-pitch entry — the PB pair included — is one scorer action: a single tap voids it whole, and it never rides along with the preceding pitch's undo unit.

A steal noticed late ("we missed the stolen base two pitches ago") is not this surface's job — that's §6's insert with `effectiveAfter`, from the stream view.

---


## 23. Design Language (the "lacks class" mandate)

The visual contract for every surface in the app — entry, stats, scouting, onboarding alike. Where
§18.7 previously held this and was nominally scoped to "stat and scouting surfaces," the build had
already outgrown that: DIA-005 and DIA-011 specify a design review pass for the pitch entry canvas,
which is a §11 surface. This section is where that authority actually lives.

**Precedence.** This section supersedes design guidance stated anywhere earlier in the spec. Where an
earlier section's *look-and-feel* instruction conflicts with §23, §23 wins and the earlier text is a
defect to be corrected, not a competing option.

The boundary matters, though, and it is narrow: §23 governs **design language** — color, hierarchy,
weight, motion, ink. It does **not** override **derived geometry** (§11.4's projection, canvas extents,
and registration), **data-model rules** (§1–§7), or **surface composition** stated in a surface's own
section (§11.4's plate anchor and control placement, §18.3's sparse-data thresholds). Those are
computed or structural, not stylistic, and a design pass does not get to relitigate them. If §23 ever
appears to contradict a derived value, that is a bug in §23.

### 23.1 Principles

Enforceable in review:

1. **Data-ink first.** No card chrome, gradients, or mascot clip-art competing with numbers. Generous
   whitespace; tabular numerals; a real typographic hierarchy (stat values large, labels small and quiet).
2. **One accent system.** Exactly one accent color is live at a time; heat maps get one
   perceptually-uniform colormap (not red-green rainbow). *Which* team's color fills the accent slot is
   contextual — §23.3.
3. **The accent goes to the datum, not the frame.** Structural elements — zone borders, card edges,
   grids — are scaffolding and stay quiet; the accent belongs to whatever carries the information, which
   on the pitch canvas is the tap marker. Structural lines on a light field are dark, not tinted: light
   blue on white vanishes in sunlight.
4. **Glanceable at arm's length in sunlight.** The dugout is the design environment: high contrast, big
   touch targets, no hover-dependent anything, dark mode for night games.
5. **Numbers carry their honesty.** Denominators and coverage always visible (§17.3); no stat rendered
   without its n.
6. **Motion is meaning.** Transitions only where they explain state change (deck advancing, count
   updating, color context switching) — never decorative.
7. **Never color alone.** Any state a coach must read — uncertainty, misplay, which team is in view —
   carries a non-color cue as well. Colorblind users are the stated reason; sunlight and cheap tablet
   panels are the practical one.

### 23.2 Semantic Reservations

Three colors carry fixed meaning app-wide and are **not available to any other purpose**, including
accents:

| Name | Color | Means | Stated in |
| --- | --- | --- | --- |
| **Dusk** | violet `#5A47A0` / `#9B85E8` | uncertainty — the count is ambiguous | §12.5, §11.2 |
| **Rosin** | amber `#E8A81C` / `#F2B935` | misplay — physical, fault not yet adjudicated | §13, §15.3 |
| **Ejection** | magenta-red `#BB1E3C` / `#F4667B` | the app failed | — |

**They do not share a color (v0.47).** Uncertainty and misplay were both amber on the reasoning that
both mean *"this needs your judgment later."* They do not ask the coach for the same thing: one says
*I do not know what happened*, the other says *I know exactly what happened and someone muffed it.*

**Size governs the treatment**, and it is why amber survives in one place and not the other. Chroma is
what separates a reserved color from Clay, but a large area of high chroma is unreadable after two
innings — so the persistent 84px count HUD takes a **tinted field with a saturated label**, while the
40px misplay chip takes a **fully saturated fill**. Rosin's separation from Clay is *lightness plus
saturation*, not hue: Clay is dark and muted, Rosin is bright and pure, which is the most robust pair
of cues in direct sun. Dusk is violet because nothing on a ball field is — it cannot be misread as
grass, dirt or blood — and because it reads *unresolved* rather than *bad*, which an ambiguous count
is.

**Rosin is a fill, never text or line work**: amber type on Chalk is illegible outdoors, so the chip
carries Ink glyphs in both themes. **Ejection is the app failing and never a fielding error** — two
phrases that mean opposite things in this product, which is exactly why they cannot share a color; a
fielding error is Rosin's job.

**`callable` is not a reservation.** It shades which zones the call grid can call (§10.1), and the
three above are *events* — something happened, look here — where this is a standing description of
where the tool works, true of most zones most of the time. A hue of its own would put permanent alert
weight across half the grid. It is **Grass in three steps**: wash (14% fill / 34% border in light,
18% / 42% in dark) = callable · solid = called · dashed = off. The border is not optional; a 14% fill
alone reads as a smudge rather than a cell. The general rule: **a reserved color is for an event, not
a state** — anything standing and common takes a step on an existing hue.

Per §23.1.7 none of these rely on color alone — §15.3 already establishes the pattern, rendering
non-clean throw arrivals with a subtle underline rather than a reserved color precisely because they
are information, not fault.

### 23.3 Color Contexts

Diamond is used to look at two things: your own team, and one specific opponent. Color is how the app
says which. This is a contract rather than a skin — it determines what may be hardcoded anywhere in
the UI, which is why it is spec and not a theme file.

**Three tiers, one accent slot.** §23.1.2 is preserved, not weakened: exactly one accent is live at
any moment. What is contextual is its *value*, not its count.

| Tier | Covers | Changes? |
| --- | --- | --- |
| **Brand baseline** | surfaces, backgrounds, nav chrome, app bar, logo lockup, splash, onboarding, typographic scale, and §23.2's reservations | never |
| **Own-team accent** | the accent slot, by default, everywhere after onboarding | set once by the coach |
| **Opponent accent** | the accent slot, while attention is scoped to one opponent | per opponent |

- **The baseline is never overridden, including under an opponent accent.** Chrome staying Diamond's
  own is what keeps the product identifiable at exactly the moment the user is deepest in another
  team's data. The accent moves; the app does not become the other team's app.
- **Own-team *secondary* color is captured but is not a second accent.** Its one sanctioned use is a
  secondary series in own-team charts. A second highlight color appearing in the UI is a §23.1.2
  violation, not a feature.
- **§23.2 outranks team color.** A team whose actual color sits in the reserved band is a real case,
  treated in Open Question #10 rather than waved away here.

**Context follows attention, not game state.** The opponent accent is a *drill-in* condition; whether a
game is live is irrelevant to it. A scouting report read on Tuesday themes exactly as the live game
against that team does on Saturday.

- **Swaps:** an opponent's hitter cards and full-screen detail (§18.1), their book and history, the
  due-batter deck while scoped to them (§18.2), and scoring a game against them.
- **Does not swap:** the schedule and any list or index showing more than one opponent, own-team stats,
  roster, development view (§22), settings, and onboarding.
- The rule underneath: **baseline accent means browsing; opponent accent means one team has your
  attention.** A schedule rendered in eight accents is decoration competing with data (§23.1.1), and it
  destroys the signal by making it constant.
- **Observation mode (§19.5) needs no special case:** you are the observer and neither participant is
  yours, so drilling into either team's book is an ordinary opponent context.

**Color is data; the scheme is derived.** A team record carries a color as a value; the rendered scheme
is computed from it at read time, exactly as every number in Diamond is computed from its events
(§1.3). A stored, baked palette is the same class of bug as a stored count — it can silently disagree
with its source.

- **Derivation guarantees legibility; the seed does not.** Seeds are arbitrary — coaches pick their real
  team color, and some of those are yellow, white, or near-black. Contrast in both light and dark
  (§23.1.4 — night games are real) is the derivation's responsibility, never an assumption about the seed.
- **An unset opponent color falls back to the baseline accent.** Never auto-assign; an invented color is
  indistinguishable from a chosen one and will be read as fact.
- **Context carries a persistent non-color label** naming the team in view (§23.1.7). Two opponents'
  colors can be near neighbours no derivation can separate.

### 23.4 Fidelity Is Per-Surface

Generalized from §11.4, where it was first stated for the pitch canvas and where it plainly applies
more broadly:

- **Entry surfaces** — pitch canvas, field canvas, call grid — are used at speed, in sunlight, on a
  clock, over a hundred times a game. Every decorated pixel competes with the markers and grids that
  carry the information.
- **Review surfaces** — stats, books, hitter cards, development views (§18, §22) — are used at leisure,
  indoors, with the data already in place. Full richness is right there, and it is where a coach forms
  their impression of the product.

Craft and busyness are separable: what reads as *serious* is precision — correct proportions, exact
registration, confident hierarchy — not photographic detail. Getting the geometry right is most of what
makes any treatment look intentional.

### 23.5 Type

Two faces, and one rule for choosing between them.

**Space Grotesk carries prose. JetBrains Mono carries codes.** A code is read as a token rather than
as language — looked up, compared, or read one character at a time: the count, a wristband code
(§10.2), a fielding position, a distance in feet, a jersey number, the inning tag. Everything else is
prose, **including prose that contains a number**: "2 outs" is a sentence and stays in the prose face;
the `2` standing alone in the count HUD is not.

The rule earns its keep on numbers that change in place. A count ticking 1–1 → 2–1 in a proportional
face reflows its own row, and the eye tracks the movement instead of the value. A monospaced face
holds the digits still — the same argument §23.1.1 makes for tabular numerals, extended to the whole
class of things that are not sentences. Small letter-spaced uppercase labels take the mono face for
the same reason: an eyebrow, a section tag, a chip glyph, COUNT UNSURE are read as tags, not words.

**Type is tier 1 (§23.3).** It does not move with the team accent and it does not move with
brightness: one scale, rendered by both themes. Light text on a dark ground reads optically bolder and
some systems drop a weight step to compensate; Diamond does not. If that changes it is a decision
recorded here, not a per-screen adjustment.

**The faces ship in the bundle, never fetched.** Offline-first is the prime directive (§12.6, §19.1,
§21.5): a font resolved over the network is a blank label in a dugout with no signal, and it fails on
exactly the day it matters. Weights are the static set the scale asks for — 400, 500 and 700 — and
that set is a constraint, not an inventory. A weight that is not bundled does not fail; it renders as
the nearest one that is, which is a wrong answer indistinguishable from a choice.

The scale itself is a token set rather than prose, and lives in `app/lib/src/ui/theme/brand_type.dart`
with the design panels it was read out of. Its shape: display and headline for the things read across
a dugout, then title and body sharing the same three sizes and separated by **weight and leading
rather than by size**, then labels for text inside components.

### 23.6 Review

Frontend work runs through the frontend-design review pass. **"Serviceable" is the failure bar, not the
target.** Where a decision is genuinely contested, settle it on a real tablet in daylight rather than in
prose — the pattern §11.4 sets for canvas fidelity and §9 #9 sets for perspective tilt.

---
