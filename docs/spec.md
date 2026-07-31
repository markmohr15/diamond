# Diamond — Event Taxonomy & Pitch Entry Spec (v0.38)

**Status:** Draft for review — v0.38 replaces §10.1's authored call-zone rectangles with a **canonical 5×5 partition of 25 cells** (the 3×3 zone whose outer ring is the black, plus one off-the-plate stop each way, corners included). A team's layout is now a *grouping* of those cells rather than an independent set, so `bounds` is derived, overlaps and gaps are unrepresentable, and any two layouts roll up to a common frame — which is what keeps a player's intent history comparable across age groups whose vocabularies differ (§22). The callable set is **per pitch type and entirely the coach's**: Diamond has no opinion about which locations suit which pitch, every cell is available to every type, and narrowing is never inferred. Sparsity is what keeps the card printable, and the call screen offers only what the active card can express. Resolves Open Question #7 — no sub-zone nudge on the call side, because a nudged coordinate has no code and would grade a pitcher against a target they were never told; situational meaning ("down and away" on 0-0 versus 1-2) is read off `actualLocation` instead. §11.4 fixes what the grid draws and when — the 3x3 always, the surrounding sixteen only while a pitch is being called and only where it can be called, implied rather than painted during location entry, and one cell-sized swatch per zone. §10.3 fixes the grid's geometry (it never re-flows between pitch types), drops the now-redundant tap-and-hold chase gesture, and un-colors the pitch-type row — one accent, on the selected type, with per-type color recorded as a review-surface option rather than a calling one. v0.37 promoted the design language to its own top-level section, **§23**, leaving §18.7 a pointer stub — the old placement was scouting-scoped in name only, since DIA-005 and DIA-011 both specify a design review pass for the §11 entry canvas. v0.36 ships the **batter silhouette** on the entry canvas as a location cue rather than keeping it behind a debug flag, and answers the objection that kept it off: she is derived from the zone profile, with her knee at `y = 0` and her armpit at `y = 1`, so she tracks the rect for every batter by construction instead of being drawn at one fixed height. She is the *only* occupied-side cue — the batter's-box fill and shading are dropped from both planes — renders in the frontal plane alone, and takes no pointer events. Full history: `docs/spec-history.md`.
**Scope:** The complete catalog of game events, their payloads, coordinate systems, and the correction model. This document is the foundation of the data layer; every stat, heat map, spray chart, and scouting report is a projection over this event stream.

---

## 1. Core Principles

1. **Append-only.** Events are never mutated or deleted. Mistakes are fixed with correction events (§6). This gives us free undo, a full audit trail, and clean multi-device sync.
2. **Atomic events, not plays.** A "play" (e.g., 6-4-3 double play) is not a single record — it's a sequence of atomic events (BallInPlay → FielderTouch ×3 → RunnerOut ×2). This is what makes weird plays representable. If it happened on the field, it can be entered.
3. **Store raw, derive everything.** The count, outs, score, runners on base, batting order position — all derived by folding over the event stream. Never stored in an event payload (with a narrow exception for snapshot events, §7).
4. **Sport-agnostic core, sport-specific config.** Baseball and fastpitch softball share the taxonomy. Rule differences (courtesy runners, DP/Flex, illegal pitches, run rules) live in a per-game `RuleSet`, not in special-cased event types.

## 2. Event Envelope

Every event shares this wrapper:

```typescript
interface GameEvent<T extends EventPayload> {
  id: string;            // UUIDv7 (time-ordered, generated on device)
  gameId: string;
  seq: number;           // monotonic per-device sequence number
  deviceId: string;      // for sync conflict resolution
  createdBy: string;     // userId of the scorer
  wallClock: string;     // ISO 8601, device local time
  type: EventType;       // discriminant
  payload: T;
  corrects?: string;     // id of event this supersedes (§6)
  voided?: boolean;      // set only via VoidEvent projection (§6)
}
```

Ordering across devices is resolved by `(wallClock, deviceId, seq)` — good enough because in v1 a single device is the source of truth for scoring; secondary devices contribute annotation events only (see Open Question #5).

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
| Baseball HS (~70″) | 19.0″ | 43.0″ | 24.0″ | 0.354 | −0.792 |

  Until per-batter zone heights land, ship the 12U row as the placeholder and derive per batter thereafter.
  **Planned, not contested:** batter height becomes settable, and the *default* row is chosen by **sport and age level** rather than being hardcoded to 12U fastpitch. Everything derived from a profile — `y_ground`, the axis ratio, the top-down plane's depth extent, and the batter silhouette (§11.4) — is expressed as a function of these two numbers precisely so that drops in without a second geometry pass.

- **Rounded figures in prose are display, not source.** `y_ground` at 12U is −0.6458 and is written "≈ −0.65" for readability. Tests assert against the value computed from the canonical inputs, never against the rounded text.
- Softball vs. baseball zone dimensions are a `RuleSet` concern for *rendering* the zone overlay; the normalized coordinates themselves are sport-agnostic.

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

## 4. Event Catalog

### 4.1 Pitch Events

The heart of the app. One `PitchThrown` per pitch, always.

```typescript
interface PitchThrown {
  pitcherId: string;
  batterId: string;
  batterSide: 'L' | 'R';         // recorded per-pitch (switch hitters)
  intendedType?: PitchTypeId;     // the call
  intendedLocation?: ZoneCoord;   // the call — where the coach/catcher wanted it
  actualType?: PitchTypeId;       // what was actually thrown (may differ from call)
  actualLocation?: ZoneCoord;     // where it crossed the plate — required only when
                                  //   location capture is ON (§12.4); null = not captured,
                                  //   or the pitch bounced first (see bounceLocation)
  bounceLocation?: BounceCoord;   // set when the pitch hit the dirt before reaching the
                                  //   plate (§3.3, §11.1's dirt-band hinge). Mutually
                                  //   exclusive with an observed actualLocation — a pitch
                                  //   either arrives in the air or bounces first, never both.
  velocity?: number;              // mph, optional (radar gun)
  batterAction?:                  // observed offensive posture on THIS pitch, orthogonal
    'showed_bunt'                 //   to outcome: squared, ball not offered at ⇒ pair with
    | 'pulled_bunt'               //   ball/called_strike; squared then pulled back;
    | 'slap'                      //   running-slap footwork (swing or not per outcome);
    | 'fake_slap'                 //   slap footwork, no offer;
    | 'slash';                    //   showed bunt → full swing (butcher boy).
                                  // Absent = conventional AB posture. This records what
                                  //   the batter DID, never what was called (§20.5 non-goal
                                  //   stands: no offense-call tracking).
  outcome: PitchOutcome;
}

type PitchOutcome =
  | 'ball'
  | 'called_strike'
  | 'swinging_strike'
  | 'swinging_strike_blocked'    // in the dirt, catcher blocks — D3K risk tracking
  | 'foul'                       // may link to BallInPlay for foul coordinates
  | 'foul_tip'                   // caught by catcher = strike, distinct from foul
  | 'foul_bunt'                  // strike three on 2-strike bunt foul
  | 'in_play'                    // always followed by a BallInPlay event
  | 'hit_by_pitch'
  | 'ball_intentional'
  | 'illegal_pitch'              // softball: ball + runners advance (RuleSet-driven)
  | 'no_pitch'                   // dead ball, timeout granted mid-delivery, etc.
  | 'unknown';                   // a pitch happened; result not captured (§12.5)

// Pitch types are team-configurable, not a hardcoded enum:
interface PitchTypeDef {
  id: PitchTypeId;
  label: string;        // "Rise", "Drop", "Change", "Screw", "FB", "Slider"...
  color: string;        // for charts
}
```

Design notes:

- **Intended vs. actual is the killer feature.** `intendedLocation` + `actualLocation` gives you a *command* metric no consumer app has: per-pitch command classification (§17.4) by pitch type, pitcher, count, and inning. `intendedType` vs `actualType` catches crossed-up signals and "she can't land the drop ball today."
- Both intended fields are optional so scoring doesn't stall when nobody's calling pitches (opponent scouting mode: you don't know their calls).
- Non-swing dead-ball weirdness (catcher's interference, batter interference on the swing) is handled by follow-up events, not more outcome variants.
- **`bounceLocation` without `actualLocation` isn't a data gap.** Per Core Principle #3, the event never fabricates a `ZoneCoord` to fill the hole — projections derive a conventional below-zone coordinate (shared `x`, a fixed low `y`) from `bounceLocation` at read time, same treatment as §12.5's inferred pitches. That conventional `y` is **`y_ground` (§3.1)** — the ball was at ground level when it crossed the plate's vertical plane, so the honest convention is the one the geometry already defines rather than an arbitrary low number. Treatment: included in coarse analytics (chase %, "how often is she in the dirt") so dirt pitches don't silently vanish from heat maps, marked as derived and never used as the basis of a command judgment, since that `y` is a convention, not an observation. Command classification reads `bounceLocation` directly instead (§17.4: bounced ⇒ uncompetitive, direction `down`).

### 4.2 Batted Ball Events

```typescript
interface BallInPlay {
  pitchEventId: string;          // links to the PitchThrown
  fair: boolean;                 // foul balls with coordinates welcome (§3.2)
  trajectory: 'ground' | 'line' | 'fly' | 'popup' | 'bunt';
  contactQuality?: 'weak' | 'average' | 'hard';   // scorer judgment, optional
  landing: FieldCoord;           // FIRST contact: where it landed, hit the wall,
                                 //   or met a glove — the spray-chart point
  retrieved?: FieldCoord;        // where a fielder finally gained possession, when
                                 //   meaningfully different (gap shot rolling to the
                                 //   wall). Absent ⇒ same as landing. Throw origins
                                 //   and roll analysis use retrieved ?? landing.
  offWall?: boolean;             // hit the fence on the fly — auto-suggested when the
                                 //   landing tap sits on the §16.2 fence spline
  landingIsCaught: boolean;      // caught in the air at that coordinate
}

interface FielderTouch {
  ballInPlayEventId: string;
  fielderId?: string;            // our team: player; opponent: optional
  position: 1|2|3|4|5|6|7|8|9|10; // 10 = softball/LL 4th outfielder if used
  touchType:
    | 'fielded'                  // clean pickup of a batted ball
    | 'caught'                   // clean catch in the air
    | 'received_throw'           // clean catch of a throw
    | 'deflected'                // touched, changed direction, played by someone else
    | 'dropped'                  // failed catch — batted ball OR throw — ball was in the glove/reachable
    | 'bobbled'                  // momentary misplay, ball stays with the fielder
    | 'booted'                   // ground ball misplayed through/off the fielder
    | 'wild_throw'               // authored a throw that was offline/away
    | 'missed_catch'             // a catchable throw got past the receiver
    | 'tag_applied'
    | 'tag_missed';
  ordinaryEffort?: boolean;      // scorer judgment on misplay types: would ordinary
                                 //   effort have made the play? Diamond infers a
                                 //   default (see §13.2); scorer can override.
  receivedQuality?:              // on received_throw / missed_catch / dropped-of-a-throw:
    'clean' | 'short_hop'        //   how the throw ARRIVED. Default 'clean'. Purely
    | 'high' | 'wide';           //   developmental — never affects official scoring (§13);
                                 //   a scooped short hop is still a clean play in the book,
                                 //   but the thrower's Throw Map (§22.1) records the bounce
                                 //   and the receiver's card records the scoop.
  location?: FieldCoord;         // where the touch happened, optional
}
```

Design notes:

- The classic "6-4-3" is three `FielderTouch` events (SS fielded, 2B received_throw, 1B received_throw) plus two `RunnerOut` events. Any sequence is expressible — the 9-3 putout at first, the 2-6-2 rundown, all of it.
- **Touch types describe physics, not scoring.** There is deliberately no `error_*` touch type — whether a misplay is an official error is *derived* (§13), because "SS dropped the liner but threw the runner out anyway" contains a misplay worth tracking and zero official errors. The scorer records what happened; projections argue about the rulebook.
- Foul ball entry flow: outcome `foul` on the pitch → optional quick tap on the field for `BallInPlay { fair: false }`. One extra tap, skippable when the game is moving fast.

### 4.3 Runner Events

```typescript
interface RunnerAdvance {
  runnerId: string;
  from: 0 | 1 | 2 | 3;           // 0 = batter's box
  to: 1 | 2 | 3 | 4;             // 4 = scored
  reason: 'batted_ball' | 'walk' | 'hbp' | 'stolen_base' | 'wild_pitch'
        | 'passed_ball' | 'balk' | 'illegal_pitch' | 'error' | 'fielders_choice'
        | 'defensive_indifference' | 'dropped_third_strike' | 'catcher_interference'
        | 'obstruction' | 'wild_throw' | 'ground_rule' | 'awarded';
  enabledByTouchId?: string;     // the FielderTouch (misplay or otherwise) that
                                 //   enabled this advance — "took second on the
                                 //   throw" links to the wild_throw touch
}

interface RunnerOut {
  runnerId: string;
  atBase: 1 | 2 | 3 | 4;
  how: 'force' | 'tag' | 'caught_stealing' | 'picked_off' | 'fly_out'
     | 'strikeout' | 'strikeout_d3k_throw' | 'appeal' | 'interference'
     | 'batted_ball_contact' | 'left_early' | 'look_back_rule'   // softball
     | 'abandoned' | 'infield_fly' | 'batter_out_of_box';
  putoutTouchId?: string;        // the FielderTouch credited with the putout
}
```

### 4.4 Administrative Events

```typescript
type AdminEvent =
  | GameStart          // teams, rosters, RuleSet, FieldProfile (§16), weather
  | LineupSet          // initial batting order + positions, per team
  | BattingOrderAdjusted // mid-game order surgery: remove (reason: injury | ejection |
                        //   departed | entry_error), insert, or reorder. Vacated-slot
                        //   policy comes from RuleSet: 'skip' | 'auto_out' | 'prompt'
                        //   (sanctioning bodies differ; scrimmages allow anything).
                        //   Batter-due projection honors the adjusted order from its seq.
  | DefensiveAlignmentSet  // fielder starting coordinates; sticky until changed (§16.4)
  | InningHalfStart    // derived state checkpoint boundary
  | InningHalfEnd      // explicit half-inning close, INCLUDING before 3 outs:
                        //   reason: 'three_outs' (implied/auto) | 'run_cap' | 'time_limit'
                        //   | 'walkoff' | 'mercy' | 'coach_agreement' | 'suspended' | 'other'.
                        //   Projection treats as authoritative; per-inning run caps in
                        //   RuleSet can auto-suggest it when the cap is reached.
  | Substitution       // playerIn, playerOut, batting slot; RuleSet validates
                       //   re-entry (softball starters may re-enter once)
  | DPFlexChange       // softball DP/Flex state transitions
  | CourtesyRunner     // for pitcher/catcher, RuleSet-gated
  | PositionChange     // defensive shuffle, no batting order change
  | PitchingChange     // convenience wrapper over PositionChange for projections
  | GameSuspended | GameResumed | GameEnd
  | DeviceRegistered    // device joins the game session: deviceId, deviceName
                        //   ("Mark's iPad"), userId, role (§12.2) — provenance anchor
  | RoleChanged         // primary/secondary transfer or capability grant (§12.2)
  | CaptureSettingsChanged  // toggles pitch-calling / location capture mid-game (§12.4)
  | CountCorrection     // authoritative count checkpoint: { balls, strikes } (§12.5)
  | EarnedRunOverride   // scorer judgment overriding §13.3's earned/unearned
                        //   derivation for one scored run: { runEventId, earned,
                        //   note? } (§13.5)
  | RbiOverride         // scorer judgment overriding RBI credit for one scored
                        //   run: { runEventId, rbi, note? } (§13.5)
  | ScorerNote;         // free-text or tagged note pinned to the last event —
                        //   "squared up the rise ball", "limping after that AB"
```

`ScorerNote` with a tag vocabulary (configurable) is the seed of the scouting report narrative layer — cheap to enter, valuable to aggregate.

### 4.5 Rule Call Events

Umpire rulings are first-class events — the judicial sibling of the physical `FielderTouch`. Runner consequences link to them the same way advances link to misplays.

```typescript
interface RuleCall {
  callType:
    | 'interference_batter'      // e.g., contact with catcher's throw
    | 'interference_runner'      // contact with fielder making a play / batted ball
    | 'interference_catcher'     // catcher's interference — batter awarded first
    | 'interference_spectator'
    | 'obstruction'              // fielder impedes runner without the ball
    | 'infield_fly'
    | 'ground_rule'              // ball out of play / lodged — awarded bases
    | 'dead_ball_award'          // overthrow out of play, HBP awards, etc.
    | 'look_back_violation'      // softball
    | 'illegal_pitch_ruling'     // when it carries base awards beyond the ball
    | 'umpire_reversal';         // call changed after conference — see note
  againstPosition?: number;      // fielder involved (obstruction, CI)
  runnerId?: string;             // runner involved (interference, LBR)
  location?: FieldCoord;
  note?: string;
}
```

- `RunnerAdvance` and `RunnerOut` gain an optional `enabledByCallId` alongside `enabledByTouchId` — "awarded second on the obstruction" links to the call exactly as "took second on the throw" links to the wild throw.
- `umpire_reversal` exists because it happens and because a correction chain (§6) on the affected events, anchored to the reversal call, preserves both what was originally ruled and why the book changed — provenance for the "wait, why does the book say that?" conversation next week.

## 5. What Is Deliberately NOT an Event

Count, outs, score, runners, batting order position, pitch count, times through the order — all **projections**. The projection engine folds the event stream into a `GameState` snapshot, and every one of these is a pure function of the stream. This is the invariant that makes corrections work: fix the event, replay, and every downstream number is automatically right.

## 6. Corrections & Undo

- **Undo (last event):** append `VoidEvent { targetId }`. The UI's undo button voids the most recent non-void event. Instant, unlimited depth.
- **Edit (any event):** append a replacement event with `corrects: <originalId>`. Projections use the latest version in a correction chain.
- **Insert (missed event):** rare, but real ("we missed the stolen base two pitches ago"). Appended with an `effectiveAfter: <eventId>` ordering hint. The UI for this can be v1.1 — but the data model supports it from day one so we never migrate for it.

## 7. Snapshots (Performance)

Replaying 250+ events per game is fast, but `InningHalfStart` events carry an optional embedded `GameState` snapshot as a checkpoint, so mid-game app restarts and multi-game stat queries don't replay from zero. Snapshots are cache, never truth — always reproducible from the stream.

## 8. Projections Roadmap (consumers of this taxonomy)

| Projection | Key inputs |
| --- | --- |
| Live scorebook / box score | all events |
| Pitch location heat maps (by pitcher, type, count, batter side) | PitchThrown |
| **Command classification** (executed / competitive / uncompetitive + direction, §17.4) | PitchThrown |
| Spray charts incl. foul tendencies | BallInPlay |
| Batter heat maps (swing %, whiff %, contact quality by zone) | PitchThrown + BallInPlay |
| Count-state tendencies (first-pitch swing %, 2-strike approach) | PitchThrown |
| Catcher framing/blocking proxy, D3K exposure | PitchThrown |
| Scouting report generator (narrative, via Claude API) | everything + ScorerNotes |

## 9. Open Questions (for Mark)

1. ~~**Pitch calling as a separate flow?**~~ **RESOLVED (v0.2):** Diamond *is* the calling mechanism. Coach taps the call, Diamond produces the three-digit wristband code, coach yells it. Single device, call-first ordering. Second-device `PitchCalled` deferred to v2. See §10–11.
2. **Velocity:** worth a quick-entry field in the pitch flow, or a distraction? (Radar data could also be batch-imported later.)
3. **Fielder touch granularity for opponents:** when scouting the other team, do you want full fielding sequences, or just position numbers with no player identity?
4. **Trajectory granularity:** is ground/line/fly/popup/bunt enough, or do you want launch-angle-ish buckets (e.g., low line vs. high line)?
5. ~~**Multi-device roles in v1:**~~ **RESOLVED (v0.3):** flexible one- or two-device operation with a primary/secondary model, full per-event provenance, and per-capability capture toggles. See §12.
6. **Tag vocabulary for ScorerNote:** want to draft the starter set now (e.g., `chased`, `late`, `early`, `squared_up`, `bad_baserunning`, `great_play`)?
7. ~~**Call-entry interaction for the freeform path (§10.1 v0.18):**~~ **RESOLVED (v0.38):** the coach picks a zone off the grid; there is no sub-zone nudge on the call side. A nudged coordinate has no code — §10.2 keys codes to (pitch type × call zone) — so refining intent past the zone would record a target the pitcher was never told, then grade them against it in §17.4. Situational variation in what a zone *means* ("down and away" as the black on 0-0, off the corner on 1-2) is read off `actualLocation` against the count, not captured as intent. Freeform capture remains for contexts with no call at all: solo scoring, verbal calling, observation mode (§19.5).
8. ~~**Scenery cap and batter's-box legibility (§11.4 v0.26–v0.28):**~~ **RESOLVED (v0.31):** the cap was protecting grid legibility, which a distance fade protects without truncating the ground furniture. Ground is drawn to its natural extent and bounded by contrast instead; the inner and front chalk lines both render, and the boxes read as boxes. Fade endpoints tune with the fidelity treatments (§11.4), not as a separate question.
9. **Should the ground perspective tilt per batter handedness (§11.4)?** The canvas renders at azimuth 0 — camera directly behind the plate — so the plate is a symmetric trapezoid with no tilt. Broadcast reference footage is shot off-axis, which reads more naturally, and a batter does stand on one side, so the symmetric view is a mild fiction. Against: an off-axis camera breaks the exact lateral registration §11.4 requires and tests for, and the zone grid stays orthographic regardless — so only the ground furniture would tilt, risking a visible mismatch between the grid and the dirt beneath it. **Shelved: not required for v1 or Milestone 1, and explicitly out of scope for DIA-011.** Settle it on a real tablet if it ever matters, not on paper.
10. **Accent seeds that collide with the semantic reservations (§23.2).** Amber and red carry meaning (§12.5, §13); some teams' actual colors sit squarely in that band. Three candidate resolutions, none obviously right: shift the accent out of the reserved band at derivation time (honest signal, but the coach's team color renders "wrong," which they notice immediately and read as a bug); keep the seed exact and lean on the non-color cues §23.1.7 already requires (§15.3's underline convention sets the precedent, but adjacency is still confusable at a glance in sunlight); or constrain the picker so the reserved band is unofferable (simple, never surprising afterward, but it tells a coach their team color is unavailable, which is a hard thing for the app to say). **Settle on a real tablet with a real team's real color.** Not blocking DIA-012, which builds the plumbing and a placeholder palette; blocking whichever ticket ships the picker.

---

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

## 11. Per-Pitch Entry Flow

The loop that runs 120+ times a game. Tap budget per pitch, full mode: **4** (type, zone → code; actual location; outcome confirm).

### 11.1 The Loop

```
┌─► [CALL]    tap type → tap zone → CODE DISPLAYED (yell it)
│   [PITCH HAPPENS]
│   [ACTUAL]  one tap on the zone canvas = actualLocation; a release in
│             the dirt band hinges the view to a top-down plate plane —
│             a second tap there = bounceLocation (§3.3)
│             Diamond suggests an outcome from context (tap location,
│             count, swing inference impossible → suggestion only):
│             big confirm button + small override row
│   [OUTCOME] confirm (1 tap) or override (1 tap)
│   ├── ball/strike/foul ──────────────► back to CALL (count advances)
│   ├── foul (optional +1 tap) ─► quick field tap for foul coordinates
│   └── in_play ─► [FIELD] tap landing spot → trajectory (5 buttons)
│                  → fielding sequence entry → runner resolution
└───────────────────────────────────────◄ back to CALL, next batter/pitch
```

- **Outcome suggestion logic:** location well out of zone → suggest `ball`; in zone → suggest `called_strike`; the override row always shows the full set (swinging, foul, foul tip, in play, HBP, illegal). Suggestion ≠ auto-commit — one tap is always required, because the ump's call is the truth, not the location.
- **Batter-action chips:** a small optional row on the outcome step — `bunt` / `pulled` / `slap` / `fake` / `slash` — one tap when the batter showed something, untouched otherwise (absent = conventional posture). Also settable post-hoc from the pitch summary, since "wait, was she squared?" is a between-pitches realization. Sticky suggestion: if the previous pitch of the AB carried an action, the row pre-highlights it for quick repeat.
- **Fielding sequence entry:** after the landing tap, a position diamond appears; the coach taps positions in order (6 → 4 → 3), long-press a position for the error variants. Runner resolution screen shows the bases with drag-to-advance / drag-to-out. This is the deepest sub-flow and gets its own spec section (v0.3) with every GameChanger-broken play as a test case.
- **Dirt-band hinge (§3.3, composition in §11.4):** the zone canvas extends below the zone rect into a visually distinct dirt band — everything below **`y_ground` (§3.1)**, and only that. Ground drawn in front of the plate projects above the ground line and is scenery, not trigger (§11.4); the two regions are different shapes, and drawn ground spans the boundary. This boundary is derived, not tuned: above the ground line a pitch can still be in the air, below it a pitch cannot, so the physically meaningful line and the interaction trigger are the same line. The band is still a *visual* target (the coach aims at dirt, not at a number), but where the dirt starts is no longer a layout preference, and the golden tests assert its position rather than approving a look. A release inside that band hinges the canvas to a top-down plate/dirt plane sharing `ZoneCoord`'s lateral axis; a second tap there sets `bounceLocation`'s depth. The swap happens **on release, not on arm** — the entire press-drag-preview stays in the frontal plane, so the existing arm-low-drag-up-to-correct grammar keeps working (coordinate spaces never change mid-gesture); only a release landing in the dirt band triggers the hinge, and the second placement is its own independent gesture. Skipping the second placement and using the skip-location affordance (§11.2) records "in the dirt, depth unknown" — a `BounceCoord` carrying `x` and no `depth` (§3.3) — with no separate tap-vs-drag heuristic needed. In that plane the two controls narrow to match: Cancel becomes **Back to zone** (un-hinges, commits nothing) and skip becomes **Depth unknown**.

### 11.2 The Mode Ladder (degradation under pressure)

| Mode | Captures | When |
| --- | --- | --- |
| **Full** (default) | call + actual + outcome + batted ball detail | normal game flow |
| **Scorer** | actual + outcome (skip call — e.g., opponent at bat, or catcher calling her own game) | opponent half-innings, tempo spikes |
| **Bailout** | outcome only — one giant BALL / STRIKE / IN-PLAY row | chaos: conferences, injuries, arguments |

- Mode is *per-tap-sequence*, not a settings toggle: the actual-location canvas has a persistent "skip location" affordance, and a two-finger swipe drops to bailout for the current pitch. The ladder exists to protect the one invariant that matters: **the count and game state are never wrong.** Heat maps survive 15% missing locations; a scorebook that disagrees with the umpire kills the app's credibility permanently.
- Opponent half-innings default to Scorer mode with the batted-ball flow emphasized (their spray data is the scouting payload) — no calling UI shown.

### 11.3 State the Loop Manages Automatically

Batter advance (from lineup projection), count reset, inning flip, pitcher's pitch count, forced-runner suggestions on walks (auto-generate `RunnerAdvance` events, coach confirms), courtesy-runner prompts when the pitcher/catcher reaches base (RuleSet-gated), and D3K arming (uncaught third strike with first base open / two outs → Diamond prompts the runner resolution instead of assuming the out). Undo is always one tap, top-level, unlimited depth (§6).

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
| Baseball | 48″ × 72″ | 6″ | 36″ / 36″ |
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
- **Batter's boxes flank the plate**, unshaded as in the frontal plane, and the lateral axis stays in register with the frontal plane above it. **Inner and front lines render; back and outer do not** — the same rule the frontal plane follows, and whether the front line is *visible* falls out of `RuleSet` rather than being special-cased: baseball's box terminates 2.29 ft out front, inside this canvas, while fastpitch's reaches 4.0 ft and runs off the top edge. No catcher is drawn (v0.35): there is no rulebook position for one, so any mark would be invented, and nothing needs one to say which way is behind — see the orientation note below.

**Controls live outside the canvas.** Cancel, skip-location, and any mode affordance must sit in a strip outside the drawing area, not overlaid on it. Overlaid on the dirt band they occupy the hinge trigger region — a live hit-target conflict, not a cosmetic one — and the problem compounds after the hinge, since the same controls have to exist in the top-down plane where the dirt is the entire canvas.

**Fidelity is an open question, settled by field test — not by argument.** The composition matches a broadcast K-zone; how richly it should be *rendered* is genuinely contested and both positions have merit:

- **For richness:** visual craft signals a serious product. A canvas that looks thrown together undermines trust in everything behind it, and "serviceable" is the failure bar (§18.7). Broadcast and video-game K-zones look authoritative for a reason.
- **For restraint:** the entry canvas is used ~120 times a game, in sunlight, on a clock. Every decorated pixel competes with the tap markers and grid that carry the actual information.

The likely resolution, to be validated rather than assumed: a **dimensional, materially real plate and dirt** — chalk with weight, texture, honest shading — on a **neutral background**, since the contrast cost lives in a busy backdrop behind the grid, not in the plate in front of it. Note also that what reads as "serious" in a reference image is mostly *precision* — correct plate perspective, confident proportions, exact lateral registration (above) — not photographic detail; craft and busyness are separable. The geometry table above is not part of the fidelity question: it applies identically to both treatments, and getting it right is most of what makes either look intentional.

**The shadow batter is paint, never a hit target.** Wherever it ships, it renders behind the marker layer and takes no pointer events: a pitch may be recorded anywhere on the canvas, including at the batter's body, so a silhouette that swallowed taps would make the region it occupies uncapturable — the opposite of why the lateral range was widened to contain her.

**The batter silhouette is built and derived from the batter's zone (v0.36), and is off by default.** It is a location cue — a coach picks a call and reads an actual against a body, not against an empty rectangle — and a calibration instrument besides, since the zone rect visibly spanning knee to armpit is a proof no table can give. Earlier drafts kept it off the entry canvas on the grounds that `y ∈ [0,1]` is *this batter's* zone and a fixed-size silhouette is honest only for a batter of the height it was drawn at. That objection is answered rather than overridden: the silhouette is **derived from the zone profile**, with the knee at `y = 0` and the armpit at `y = 1` — definitionally the zone's own edges — so it tracks the rect for every batter by construction and cannot drift from it. Stature follows from the profile (58″ at 12U), and everything else is human proportion expressed as a fraction of it. It renders in the **frontal plane only**: its job is the vertical read, which the top-down plane has no axis for. The head is frame-cut by the +1.5 top at upper-face level, which is that trim working as designed. **What is not yet good enough is the drawing** — the figure is built from uniform-width strokes and does not read convincingly as a batter — so it is hidden pending DIA-013, and the entry canvas carries no occupied-side cue in the meantime. Visibility is a parameter rather than a constant, because a future practice state (bullpens with no batter in the box) wants the same switch driven by a user setting.

**Fidelity is per-surface.** Review and scouting screens (§18) are used at leisure, indoors, with markers already placed — full richness is right there and is where a coach forms their impression of the product. The entry canvas is the one surface where decoration competes with a job. Build both fidelities of the entry canvas behind the same coordinate mapping and compare them on a real tablet in daylight (DIA-011 golden tests).

---

## 12. Device Roles, Sync & Provenance

### 12.1 Why This Is Tractable

The two-device design rests on one rule: **device streams are disjoint.** No two devices ever author the same class of event, so merging is a pure set union — conflicts are structurally impossible. This is the CRDT easy case; no conflict-resolution UI, no last-write-wins gambling.

### 12.2 Roles

```typescript
type DeviceRole = 'primary' | 'secondary';

interface DeviceCapabilities {          // what a secondary is granted
  pitchCalling: boolean;               // emit PitchCalled events
  scorerNotes: boolean;                // emit ScorerNote events
  liveView: boolean;                   // read-only game state (always true)
}
```

- **Primary** — exactly one per game. The authoritative scorer: the only device that may emit game-state events (pitches, batted balls, runners, substitutions, corrections). Owns count/outs/score integrity.
- **Secondary** — zero or more. Emits only annotation-stream events per its granted capabilities. In the canonical two-person setup: head coach on the secondary calling pitches (`PitchCalled`), assistant on the primary scoring. Diamond works identically with the secondary absent — the primary's calling UI (§10.3) simply stays enabled.
- **Session join:** primary creates the game and displays a QR code; secondary scans to join, emitting `DeviceRegistered`. **Role transfer** ("my tablet is dying") is an explicit two-tap handshake emitting `RoleChanged` — never automatic, so there is always exactly one authoritative device and no split-brain scoring.

### 12.3 Provenance & Audit

Every event already carries `deviceId` + `createdBy` (§2); `DeviceRegistered` gives those IDs human names. Requirements:

- **Event inspector:** any datum on any screen — a pitch on a heat map, a run in the box score — is traceable to its underlying events, each showing author, device, wall-clock time, and correction chain. "Did I enter that or did my assistant?" is a tap, not a mystery.
- **Game audit view:** the full event stream, filterable by author/device/type, corrections shown inline as chains. Doubles as the debugging view during development.
- Correction events record their own author — so "Mark corrected Sarah's entry in the 4th" is visible history.

### 12.4 Capture Toggles

Not every game gets the full treatment. Capture is configured at `GameStart` and changeable any time mid-game (emits `CaptureSettingsChanged`, so the audit trail shows exactly when capture depth changed):

```typescript
interface CaptureSettings {
  pitchCalling: boolean;        // show the call screen at all
  pitchLocationOurs: boolean;   // capture actualLocation when we pitch
  pitchLocationTheirs: boolean; // capture actualLocation when they pitch
  battedBallDetail: boolean;    // full landing/trajectory flow vs. outcome-only
  defensiveAlignment: boolean;  // pre-pitch fielder positioning (§16.4)
}
```

- Toggling location capture OFF removes the zone-canvas step entirely — outcome buttons come first. The per-pitch skip affordance (§11.2) still exists when capture is ON; the toggle is for "this whole game, we're not doing that."
- Projections handle sparse data by design: heat maps aggregate whatever locations exist; command classification requires both intended and actual and simply shows coverage ("41 of 87 pitches charted") so nobody mistakes sparse for complete.

### 12.5 The `unknown` Outcome & Count Checkpoints

Reality: the scorer looks up and the count changed. Two mechanisms keep the book honest:

- **`outcome: 'unknown'`** — "a pitch happened, I don't know what it was." Keeps pitch count accurate but leaves the ball/strike count ambiguous, so the projection marks derived count **uncertain** (rendered with a visual flag, e.g., amber count display).
- **`CountCorrection { balls, strikes }`** — an authoritative checkpoint: "the scoreboard says 2-1, make it so." Entered via long-press on the count display → set the count → done. The projection treats it as an override from that point forward and clears the uncertainty flag. Retroactively, unknown pitches between the last certain state and the checkpoint are resolved by replaying candidate histories through the real count logic (aggregate arithmetic is insufficient — a known foul's count effect depends on the strike count at that exact moment), at two conservative tiers:
  - **Per-pitch:** an unknown pitch is assigned an inferred count effect only when exactly one candidate history explains the checkpoint. Inference never ties a result to a specific pitch — and to that pitch's recorded call/location data — unless it is unique in this sense; unresolved pitches keep `outcome: 'unknown'` forever.
  - **Aggregate:** when several histories match but all agree on the *multiset* of effects (2 unknowns + checkpoint at 2-1 from 1-0 = one ball and one strike, in either order), that multiset is creditable to the span as a whole — and to a pitcher only if every matching history implies the same per-pitcher multiset (mid-AB pitching changes make this non-automatic). Aggregate-tier derivation is deferred until a stat actually consumes it; the stream permanently retains everything needed to derive it later.

  Inferred effects at either tier are derived projection outputs, never synthetic events — marked as inferred, excluded from pitch-quality analytics, included in pitch counts.
- This is deliberately a narrow exception to §5's "derive everything": corrections of *reality-capture gaps* get checkpoint events (`CountCorrection` now; `BaseStateCorrection` reserved for the same pattern if field testing demands it). The projection remains a pure fold — checkpoints are just events with override semantics.

### 12.6 Transport Ladder

The sync engine is **transport-agnostic**: its only job is "exchange event batches I have that you don't" (per-device sequence vectors make gap detection trivial). Transports are pluggable pipes beneath it, attempted in order:

| Transport | When | Notes |
| --- | --- | --- |
| **Cloud relay** | any cellular/wifi on either device | ships first; reuses the post-game sync backend; store-and-forward, ~200 bytes/event |
| **Local network (websocket)** | shared wifi or a $30 battery travel router in the gear bag | trivial code; the pragmatic dead-zone answer |
| **BLE peer-to-peer** | true dead zones, no gear | custom GATT service (the only cross-platform iOS↔Android path); own milestone with real field testing — pairing UX, sleep/reconnect, iOS background modes |

Disconnection is a non-event: both devices keep working, events buffer locally, reconciliation is automatic on reconnect, and the primary's game-state integrity never depends on the link. The secondary's live view degrades to "last synced 40s ago" with a staleness indicator rather than lying with a stale count. Call→pitch linking tolerates late arrival: if a `PitchCalled` shows up after its `PitchThrown`, the projection pairs them by time adjacency.

### 12.7 Build Sequencing

v1 ships single-device (primary only) with capture toggles and count checkpoints — those matter even solo. Two-device over cloud relay is the first post-v1 milestone; local-network transport follows cheaply; BLE is scheduled when there's field-testing bandwidth to do it right.

---

## 13. The Error Model

**The core insight: GameChanger's error handling is bad because it asks the scorer to be the official scorer in real time.** Diamond asks the scorer to be a *witness* — record the physics — and derives the official scoring afterward, where it can be reviewed and recomputed. This section is the contract between those two layers.

### 13.1 Three Layers, Cleanly Separated

| Layer | Lives in | Examples |
| --- | --- | --- |
| **Physical record** | FielderTouch types, RunnerAdvance/Out links | dropped, booted, wild_throw; "runner took third *on that throw*" |
| **Judgment** | one flag: `ordinaryEffort` on misplay touches | "she should have had it" vs. "diving attempt, no play" |
| **Official scoring** | projection output, never entered *(narrow exception: §13.5)* | E5, hit vs. E, earned vs. unearned runs, 6-3 |

The scorer's in-game workload is layer 1 plus an occasional one-tap override on layer 2. Layer 3 is free.

### 13.2 How Official Errors Are Derived

The box-score projection charges an error to a misplay touch (`dropped`/`booted`/`bobbled`/`wild_throw`/`missed_catch`) when **(a)** `ordinaryEffort` resolves true, and **(b)** the misplay had a consequence: a batter reached who'd otherwise be out, any runner advanced (via `enabledByTouchId` links), or an at-bat was prolonged (dropped foul fly). A dropped liner recovered in time to record the out anyway → misplay logged, no error charged. Both facts survive: the official book stays clean and the SS's development report still shows the drop.

`ordinaryEffort` defaults: `booted`, `missed_catch`, `dropped` (on throws and routine flies) → true; `dropped` on a touch marked at an extreme location relative to the fielder's position, or on `deflected` chains → prompt the scorer. The override is a long-press on the misplay in the play summary strip — deliberately *post-hoc friendly*: the judgment can be made or changed after the dust settles, or the next half-inning, or that night, and every projection recomputes.

Hit vs. error — the judgment call GameChanger buries in a maze of play-type menus — is exactly this same flag on the *first* touch of the ball. Recorded physics: `booted`, batter reached. `ordinaryEffort: true` → E, no hit. `false` → hit, no error. One bit, flippable forever, and the spray chart doesn't care either way because the ball landed where it landed.

**Mental errors** (threw to the wrong base, held the ball too long) are officially not errors and Diamond doesn't pretend otherwise — but they're exactly what `ScorerNote` tags are for (`wrong_base`, `late_decision`), and the development projection surfaces them alongside physical misplays.

### 13.3 The Payoff: Earned Runs Actually Work

Earned-run determination requires reconstructing the inning as if errors and passed balls hadn't happened — which is impossible to do well when errors are mangled at entry, and is why GC's ER numbers are folklore. Diamond's projection replays the inning's event stream, removes error-enabled advances and error-prolonged at-bats, and determines which runs still score. Fully automatic, fully explainable (the event inspector shows *why* a run is unearned), and recomputable when an `ordinaryEffort` flag gets flipped Tuesday night.

### 13.4 Multi-Misplay Plays

Nothing special is needed — that's the point. Booted grounder, then the recovery throw sails into the fence, batter ends up on third: `booted(SS)` → `wild_throw(SS)` → advances linked to each touch respectively. Two misplays, one fielder, correctly two errors (or one, if the boot gets judged a hit). The "Little League home run" is the same pattern with more links. Entry is just taps in sequence on the position diamond; attribution defaults to the most recent misplay and is adjustable by tapping the advance arrow then the enabling touch.

### 13.5 Scoring Overrides

§13.3's reconstruction covers the mechanically derivable cases, but earned-run and RBI rulings sometimes come down to a judgment call the rule book leaves to the official scorer's discretion — no amount of physical-record modeling reaches those, because there's nothing left to derive; a human has to decide. Rather than special-case those scenarios into the reconstruction algorithm (each one bends the "removes error-enabled advances" logic differently, and the list is open-ended), Diamond gives the scorer the same override pattern already established for the count (§12.5's `CountCorrection`): a narrow, explicit exception to "derive everything" (§1.3), entered as an event, not a mutation.

- **`EarnedRunOverride { runEventId, earned, note? }`** — `runEventId` is the id of the scoring `RunnerAdvance{to: 4}` event. The projection uses the latest visible override for a given `runEventId` in place of the §13.3 derivation; with no override, derivation is untouched. Like every other event, it's flippable via the standard `corrects` chain and undoable via `VoidEvent` — no separate "clear override" mechanism needed.
- **`RbiOverride { runEventId, rbi, note? }`** — same anchor and mechanics, for RBI credit on that specific run. Per-run rather than per-batter-total: a multi-run play can need one run's credit corrected without disturbing the others (a real official-scoring pattern — e.g. a run controversially ruled non-RBI on a play that still drove in a teammate).

Both are deliberately **narrow**: they override one specific run's ruling, not a batter's whole line or a box-score total, and they carry forward the same guarantees as §13.1's derived layers — recomputable, explainable (the event inspector shows "overridden by scorer, see note" the same way it shows "unearned because E6"), and reversible. This is not a general-purpose box-score editor; a projection output that needs routine hand-correction is a sign the derivation itself is wrong and should be fixed, not routed around. These events exist for the genuine edge the rule book hands to judgment, not as an escape hatch from building the derivation correctly.

---

## 14. Acceptance Play Suite

Every play here is a design target, an entry-flow walkthrough, and — verbatim — a test fixture for the rules engine. Format: the physical sequence, the event encoding, and the expected projection outputs.

### Play #1 — Dropped liner, out recorded anyway *(Mark's founding grievance)*

Line drive to SS; she drops it, recovers, throws the batter out at first.

- **Events:** `BallInPlay{line, landing≈6}` → `FielderTouch{6, dropped, ordinaryEffort: true}` → `FielderTouch{6, fielded}` → `FielderTouch{3, received_throw}` → `RunnerOut{batter, at 1, force, putout→3's touch}`
- **Box score:** 6-3 groundout... rendered as L6-3 style putout; **no error** (no consequence). **Development view:** SS charged a dropped catchable liner. **GC status:** unrecordable.

### Play #2 — Boot, then throw away, batter to third

Ground ball booted by SS; recovery throw sails past first into dead territory... or live and batter takes third.

- **Events:** `BallInPlay{ground, ≈6}` → `FielderTouch{6, booted, OE: true}` → `RunnerAdvance{batter, 0→1, error, ←boot}` → `FielderTouch{6, wild_throw, OE: true}` → `RunnerAdvance{batter, 1→3, wild_throw, ←throw}`
- **Box:** E6 (fielding) + E6 (throwing), 0-for-1, no hit. Run scoring later by this runner: unearned. **Flip the boot's OE to false:** single + E6 throwing, advance to third on the error.

### Play #3 — Single, runner thrown out stretching, trail runner advances on the cutoff throw

Clean single to RF; batter tries for second, thrown out 9-6 tag; meanwhile R3 scored, and the *throw* let nothing else happen — variant: throw gets away, batter safe.

- **Events:** `BallInPlay{line, RF}` → `FielderTouch{9, fielded}` → `RunnerAdvance{R3, 3→4, batted_ball}` → `FielderTouch{6, received_throw}` → `FielderTouch{6, tag_applied}` → `RunnerOut{batter, at 2, tag, ←6}`
- **Box:** single, batter out 9-6, RBI. Hit and an out on the same play — a combination GC's templates fight.

### Play #4 — Dropped foul pop, at-bat continues

2-1 count, foul pop near the dugout, 3B camps under it and drops it.

- **Events:** `PitchThrown{outcome: foul}` → `BallInPlay{fair: false, popup}` → `FielderTouch{5, dropped, OE: true}`
- **Box:** E5 charged (at-bat prolonged), count now 2-2, **same batter still hitting.** If she then homers, the run is unearned. GC: no clean way to charge this while continuing the at-bat.

### Play #5 — D3K, throw away, everybody moves

Two outs, R1. Strike three in the dirt, batter runs; catcher's throw to first is wild; batter safe at second, R1 to third.

- **Events:** `PitchThrown{swinging_strike_blocked}` → `RunnerAdvance{batter, 0→1, dropped_third_strike}` → `FielderTouch{2, wild_throw, OE: true}` → `RunnerAdvance{batter, 1→2, wild_throw, ←throw}` → `RunnerAdvance{R1, 1→3, wild_throw, ←throw}`
- **Box:** K for the pitcher (yes, a strikeout with no out), E2, runners at 2nd/3rd. Pitcher's K/inning ledger and the earned-run reconstruction both handle it.

### Play #6 — Rundown with a dropped exchange

R1 picked off; 3-6-3-4, second baseman drops the last exchange, runner dives back safe.

- **Events:** `FielderTouch{3, wild?no—received}` sequence: `{3 fielded(pickoff throw received... modeled as received_throw)}` → `{6 received_throw}` → `{3 received_throw}` → `{4 missed_catch, OE: true}` → `RunnerAdvance{R1, back to 1, error, ←4}` *(a from==to "advance" records surviving the rundown on the misplay)*
- **Box:** E4 only if the runner would otherwise have been out — OE flag carries it; pickoff attempt logged for the pitcher/catcher ledger either way.

*(Suite grows with every play Mark supplies; each entry ships as a rules-engine test fixture.)*

---

## 15. Field Entry UI — Drag, Throw, Modify

The interaction model keeps what GC got right — dragging the ball around the field *is* the natural grammar for a play — and fixes the part that's broken: there was never a place to say "and something else happened right here."

### 15.1 The Canvas

After the landing tap + trajectory (§11.1), the play canvas shows the field with fielders at their positions and the ball at its landing point. The landing entry itself is one gesture with two grips: a **tap** records `landing` alone (routine balls — retrieval assumed at the same spot), while a **tap-and-drag** records `landing` at touch-down and `retrieved` at release — the gap shot is one continuous motion tracing the ball's roll, no extra taps, no mode. A landing on the fence spline auto-suggests `offWall`.

- **Tap a fielder** = that fielder touched the ball (`fielded`/`caught` inferred from trajectory + whether the landing was marked caught).
- **Drag the ball** from the current fielder to another = a throw; the receiver gets `received_throw`.
- **Drag a runner** to a base = advance; **drag a runner to an out affordance at a base** (or flick toward the dugout) = out, with `how` inferred from context (force vs. tag from the base state, fly out from a caught ball) and confirmable.
- Runner advance arrows auto-attribute to the most recent touch/misplay; tap an arrow to re-attribute.

### 15.2 The Play Chain Strip

As the sequence builds, a horizontal strip above the canvas renders it as nodes: **⚾ → 6 → 4 → 3**, with runner consequences hanging beneath the touch that caused them. This strip is the play's visible event log — and every node is a live control.

### 15.3 The Modifier Chip — "something else happened here"

Every node in the chain carries a small **"+" chip**. Tapping it opens a compact radial/sheet menu scoped to what makes sense *at that point in the sequence*:

- **On a touch node:** the misplay set — `dropped`, `booted`, `bobbled`, `wild_throw` (converts the following drag's meaning), `missed_catch`, `tag_missed`. On a **receiving** node (`received_throw` and friends), the same chip also offers throw-arrival quality: `short hop` / `high` / `wide` — one tap, recorded as `receivedQuality`, zero effect on official scoring. Selecting a misplay recolors the node (misplays render amber; non-clean arrivals render with a subtle underline, not amber — they're information, not fault); on commit, misplays trigger the `ordinaryEffort` inference or prompt (§13.2).
- **Between nodes / on a runner:** the `RuleCall` set — obstruction, interference variants, ground rule, dead-ball award. These insert a call node (rendered ⚖) into the chain at that position, and subsequent runner drags can link to it.
- **On the ball's landing node:** infield fly, fair/foul dispute → `umpire_reversal`, spectator interference.

One mechanic, uniformly placed, covering errors *and* the weird stuff — no modes, no menu maze. The common case costs zero extra taps; the exceptional case costs exactly one tap plus one selection, at the exact spot in the play where it happened.

### 15.4 When the Misplay Gets Entered — Three Moments

1. **In the moment:** tap the chip mid-sequence as described. Fastest when the scorer saw it clearly.
2. **Prompted:** Diamond notices when the physics don't add up and asks. Ball dragged to first *before* the batter-runner arrives, but the batter was marked safe → "Did 3 drop the throw / was the throw wild?" Chain ends at a fielder with no out and no advance-attribution → "bobble?" These prompts appear as a single dismissible chip suggestion, never a blocking dialog — the count screen is always one tap away.
3. **Post-hoc:** every committed play stays editable from the play summary strip (and the audit view). Long-press → the same canvas + chain reopens. This is where hit-vs-error judgments get settled between innings or after the game, emitting correction events (§6) with full provenance.

The design bet: moments 2 and 3 carry most of the load. In-game, the scorer's job is drags and taps that mirror what her eyes saw; adjudication is deferrable by construction, because the physical record is complete without it.

### 15.5 Commit & Undo

Nothing enters the event stream until the play is committed (tap the ✓ when the chain matches reality, or auto-commit when the next pitch's call screen is invoked with a consistent base/out state). Commit emits the whole event sequence atomically — `BallInPlay`, touches, calls, runner events — so undo (§6) of a play voids it as a unit, and a half-entered play never corrupts game state on a crash or a dead battery: uncommitted canvas state is journaled locally and restored on relaunch.

---

## 16. Field Profiles & Defensive Alignment

### 16.1 The Profile & the Defaults Hierarchy

```typescript
interface FieldProfile {
  id: string;
  label: string;                  // "Seymour Smith Field 3", "12U Default"
  sport: 'baseball' | 'softball';
  source: 'builtin' | 'team' | 'game';
  fence: {                        // feet, the five poles of the fence model
    lfLine: number;               // left-field foul pole      (θ = −45°)
    lfGap: number;                // left-center gap           (θ = −22.5°)
    cf: number;                   // dead center               (θ = 0°)
    rfGap: number;                // right-center gap          (θ = +22.5°)
    rfLine: number;               // right-field foul pole     (θ = +45°)
  };
  basePath: number;               // 60 / 65 / 70 / 90 ft
  pitchingDistance: number;       // 35 / 40 / 43 / 46 / 50 / 60.5 ft
  backstop?: number;              // ft behind the plate; affects foul-territory render
}
```

Resolution order at `GameStart`: **per-game override → team profile pick → builtin(sport, age group)**. Teams keep a **profile library, not a single default**: multiple named profiles ("Our 12U field", "Playing up — 14U", "Seymour Smith Field 3"), one marked default, all one tap at game creation. This is for the extremely common playing-up dynamic — same roster, different pitching distance and base paths depending on the tournament — and *every* dimension is per-profile: the five fence poles, `basePath`, `pitchingDistance`, backstop. A coach at an unfamiliar park adjusts the numbers once, names it, and it's in the library forever.

**Builtin presets** — draft values, to be finalized with real sanctioning-body specs before ship (⚠ verify):

| Preset | Fence (line/gap/CF) | Base path | Pitching |
| --- | --- | --- | --- |
| Fastpitch 10U | 180 / 190 / 200 | 60 | 35 |
| Fastpitch 12U | 190 / 200 / 210 | 60 | 40 |
| Fastpitch 14U+ / HS | 200 / 210 / 220 | 60 | 43 |
| Baseball LL Majors | 200 / 200 / 200 | 60 | 46 |
| Baseball 50/70 | 225 / 250 / 275 | 70 | 50 |
| Baseball HS | 320 / 365 / 390 | 90 | 60.5 |

(Symmetric defaults; real parks aren't, which is exactly why the five numbers are editable.)

### 16.2 The Fence Model

The fence is a smooth curve interpolated through the five points (monotone cubic spline over θ ∈ [−45°, +45°] → r). This gives `fenceDistanceAt(θ)` for any bearing — used for rendering the outfield wall, deriving `fenceRelativeDepth` (§3.2), classifying wall-ball/over-the-fence taps, and drawing an honest warning track. Five points is enough to capture the classic asymmetric park; a v2 `customVertices` escape hatch is reserved in the schema for the truly weird ones.

### 16.3 Rendering & Entry Scale

The field canvas renders **to scale from the profile**: the infield diamond from `basePath`, the circle/mound from `pitchingDistance`, the fence from the spline. Consequences:

- A batted-ball tap is a real coordinate in feet — Diamond shows the distance live during the tap ("214 ft") so the scorer can sanity-check against what they saw.
- Ball-flight sanity: taps beyond the fence prompt HR/ground-rule classification automatically, because the canvas *knows* where the fence is on this field today.
- The same swing shows up honestly across parks: absolute feet on the per-game view, fence-relative depth on aggregated spray charts.

### 16.4 Pre-Pitch Defensive Alignment

`DefensiveAlignmentSet` records each fielder's starting coordinate (`position → FieldCoord`). **Sticky semantics:** emitted when alignment changes, not per pitch — every `PitchThrown` implicitly inherits the current alignment via projection join, so the event stream stays lean while every pitch still knows where the defense stood.

- **Entry:** on the field canvas, drag fielders from their standard spots (profile-scaled defaults per position). Team-defined **alignment presets** — "slapper defense," "bunt corners in," "no-doubles" — apply with one tap and can be tweaked after applying. Preset library lives at the team level.
- **Capture-toggle gated** (§12.4: `defensiveAlignment: boolean`) — like pitch locations, this is depth you turn on when you have the bandwidth, most naturally when charting your own defense or scouting a specific opponent.
- **The analytics payoff, in ascending order of ambition:** (1) spray charts overlaid with where the defense actually stood — "the gap shot was a positioning miss, not a range miss"; (2) fielder range read directly: landing coordinate minus starting coordinate on balls in their sector; (3) opponent alignment scouting — record *their* alignment against *your* hitters, and the scouting report can say "they play their corners deep on Emma; bunt."

---

## 17. Stats & The Filter Model

### 17.1 The Architectural Free Lunch

Every stat in Diamond is a **pure function over a set of events**. That single fact makes filtering a solved problem before it starts: a filter is just the selection of which events feed the fold. GC's filters are limited because their stats are precomputed rows keyed by game; when the row doesn't exist for your question, the answer doesn't either. Diamond's answer to "OBP over the last three weekends, vs. left-handed pitching, with runners on" is the same code path as season AVG — a different event selection, the same fold.

```
stat(filterSelect(allEvents)) → number
```

### 17.2 Filter Dimensions

**Scope filters** (select games):

- **Game(s)** — multi-select
- **Date range** — any start/end; presets: last 7/30 days, this month, custom
- **Tournament/Event** — games carry an optional `tournamentId`; coaches think in tournaments, and "how did we hit at state?" should be one tap, not a date-picker exercise
- **Season** — team-defined date-range container with a name
- **Opponent**, **home/away**
- **Game type** — from a team-configurable taxonomy seeded with: league, tournament, exhibition/friendly, scrimmage, showcase (regional vocabularies differ; teams add their own). Each type carries a `countsTowardStats` default (scrimmage: off) — overridable per game, and every stat view can toggle excluded types back in.
- **Tags** — freeform, multiple per game ("bracket play", "vs. lefty starter", "rain-shortened"). Filterable individually or in combination; tag vocabulary auto-completes from the team's history.

**Split filters** (select events within games — the Diamond-only tier):

- vs. batter/pitcher handedness · by count state (ahead/behind/even/2-strike/3-ball) · by pitch type · runners on / RISP / bases empty · by inning · times-through-the-order · by call zone · by batter action (showed bunt / slap / etc.)

**Saved filters:** any combination is nameable and pinnable ("Fall vs. Elite teams", "2-strike ABs"). A saved filter + a stat view is a bookmark — the coach's dashboard is just pinned bookmarks.

### 17.3 The Catalog

**Tier 1 — table stakes (GC parity, correctly computed):**

| Domain | Stats |
| --- | --- |
| Batting | G, PA, AB, H, 2B, 3B, HR, R, RBI, BB, HBP, K, SB, CS, SAC, SF, AVG, OBP, SLG, OPS |
| Pitching | G, GS, IP, BF, H, R, **ER (per §13.3 — actually right)**, BB, HBP, K, W/L/SV, ERA, WHIP, K/BB, pitch count, pitches/inning |
| Fielding | PO, A, E, FPCT, DP |
| Catching | SB allowed, CS, CS%, PB |

Softball rendering nuances via `RuleSet`: 7-inning ERA normalization, tie games, run-rule finals annotated.

**Tier 2 — pitch-level (impossible without Diamond's data):**

| Domain | Stats |
| --- | --- |
| Plate discipline | swing %, chase % (swings out of zone), whiff %, contact %, first-pitch swing %, pitches/PA |
| Batted ball | GB/LD/FB/PU %, hard-hit % (contactQuality), avg distance, pull/center/oppo %, foul-ball direction tendencies |
| Pitcher command | strike %, first-pitch strike %, **execution rate / uncompetitive rate by pitch type (§17.4)**, miss-direction bias, zone % by count, called-strike edge % |
| Pitch mix | usage % by type, by count, by batter side; velocity if captured |
| Catcher | blocks per D3K opportunity, D3K conversion against |
| Defense | misplays (charged-or-not, §13), range (landing − start, §16.4) |

Tier 2 stats degrade gracefully with capture gaps (§12.4): each shows its denominator coverage ("41 of 87 pitches located") so sparse never masquerades as complete.

### 17.4 Command Classification

**Why not miss distance.** Intent is a region, not a point. `intendedLocation` is a call zone's centroid or a finger-tap standing in for one (§10.1) — either way the real target is inches wide, before any tap error on a moving object. The honest error bar on any single miss is inches, so "average miss: 7.2 in" is false precision wearing an authoritative face. Diamond therefore classifies command into buckets wider than the noise, and reports direction separately.

**The three buckets**, judged against the call, not against the strike zone alone:

| Bucket | Meaning |
| --- | --- |
| **Executed** | hit the target region |
| **Competitive miss** | missed the target, but the pitch still plays — in the zone or on its edges; a hitter has to respect it |
| **Uncompetitive** | no realistic strike and no realistic chase — nobody is swinging |

**One rubric, via zone resolution** (§10.1). The target region is always a call zone's `bounds`, resolved in this order:

1. `intendedZoneId` is set (grid call) → that zone.
2. `intendedZoneId` is null (freeform tap) → the zone whose `bounds` contain `intendedLocation`. Because the layout covers out-of-zone space as well as the strike zone, a freeform tap lands inside a zone nearly every time — the coach pointing at "low and away off the plate" is pointing at a region that exists.
3. No zone contains the point (a tap well outside everything) → nearest zone by centroid, **marked as inferred** wherever the resolution changes a bucket.

Executed = `actualLocation` inside the resolved zone's `bounds`. Freeform capture is therefore no coarser than grid capture in the common case; the honest gap is only at step 3, and it announces itself.

The team's own layout serves as the measuring grid even when charting an opponent's pitcher (§19.5) — it's a yardstick, not a claim about what they called.

**Miss direction** is reported alongside and stays coarse: arm-side / glove-side / up / down, handedness-resolved per §3.1 so "arm-side" means the same thing for every pitcher. Direction survives noise that magnitude doesn't — "she misses arm-side late in games" is a real observation at this resolution.

**Chase-call inversion.** When the resolved zone is a chase call — its centroid sits outside the strike-zone rect, derived not stored (§10.1) — the rubric inverts: burying the 0-2 drop ball or running one off the outside corner *is* execution, and catching too much plate is the miss — a chase pitch that leaks over the plate is the dangerous outcome, and gets classified as such. Because resolution (above) yields a zone for freeform taps too, this is determined the same way for both producers; no guessing is required. Nothing in the data model changes — this is entirely projection.

**Bounced pitches** (§3.3) are read from `bounceLocation` directly — no cross-plane magnitude is computed, because none is needed. Against a strike call, a bounce is uncompetitive with direction `down`. Against a chase call meant to be buried, it is execution: the pitch did exactly what it was asked to do. Bounce depth stays where it's genuinely informative: catcher blocking difficulty (§17.3), and how far short a developing drop ball is finishing.

**Reported as:** execution rate and uncompetitive rate, sliceable by pitch type, count state, inning, and time through the order (§17.2) — "fine through four, then uncompetitive on 30% of drop balls" is a pitch-count conversation; "uncompetitive rate spikes when behind" is a confidence conversation. Neither needs an inch.

**Thresholds are tunable, forever.** Bucket boundaries live in projection config, not in events, so field-testing what "competitive" means recomputes every game ever charted. Ship with defaults, expect to revise them, never migrate data to do it.

### 17.5 Performance Model

Per-game aggregate snapshots are cached at `GameEnd` (and invalidated by corrections). Scope filters fold cached per-game aggregates — a season of date-range queries is summing ~40 small structs. Split filters that cut *within* games replay events, but a game is only ~250 events; a full season replay is <10⁴ events, trivially interactive on-device. No server round-trip required for any stat view: the stats engine runs entirely on the local store, which is what "works at a field with no signal" demands anyway.

---

## 18. The Scouting View

### 18.1 The Opponent Book & the Hitter Card

Every opposing team accumulates a **book**: everything ever charted against them, with the full §17 filter model available (a book filtered to "this season" or "last two tournaments" is one tap). The unit of the book is the **hitter card** — one glanceable panel per player:

```
┌──────────────────────────────────────────────┐
│ #7 M. Rodriguez  ·  R/R        🚩 (2 notes)  │
│ .412 / .458 / .647  ·  24 PA charted         │
│ ┌─────────┐  ┌─────────┐   1st-pitch swing % │
│ │  ZONE   │  │  SPRAY  │   chase %  ·  K %   │
│ │ heatmap │  │  chart  │   GB/FB  ·  pull %  │
│ └─────────┘  └─────────┘   [tendency chips]  │
└──────────────────────────────────────────────┘
```

- Slash line + PA-charted count (the honesty denominator, always visible), the zone heat map, the spray thumbnail, and 4–6 headline tendencies rendered as chips: `1st-pitch swinger` · `chases up` · `dead pull` · `slapper` · `won't swing 3-1`. Chips are derived from thresholds on Tier 2 stats, not hand-entered.
- Tap the card → full-screen detail: large heat map with metric switching (§18.3), full spray chart with filters, count-state breakdowns, every note and every AB against, pitch by pitch.

### 18.2 Lineup Order & the Due-Batter Deck

The book's default sort is jersey/alpha — until the opposing `LineupSet` is entered (from the pregame card exchange), at which point **the deck reorders 1–9 in their batting order**, subs appended below. Pregame prep is then literally reading the deck top to bottom.

In-game, the deck becomes live: the projection knows who's due, so the deck auto-advances — current batter's card front and center, on-deck peeking. On a secondary device (§12.2) this is the assistant's whole job done for them; on the primary it's one swipe away from the call screen.

### 18.3 Zone Heat Maps

- **Metrics, switchable:** pitches seen · swing % · whiff % · contact quality · batting results (per-zone AVG-style) — each answers a different pregame question ("where does she chase?" vs. "where does she do damage?").
- Rendered from `ZoneCoord` via kernel density over the normalized zone, batter-handedness oriented (inside/outside labeled per §3.1's flip rule), zone rectangle overlaid.
- **Sparse-data honesty:** below a per-metric threshold (default n=15 pitches), Diamond renders discrete dots, not a smoothed surface — a KDE over six pitches is a lie with good color grading. The n is always displayed on the map.

### 18.4 Batted-Ball Profile

The spray chart (fence-relative rendering per §3.2, foul territory included) plus the distribution row: GB/LD/FB/PU %, pull/center/oppo %, hard-hit %, bunt/slap frequency. Overlay toggle for defensive-alignment data when captured (§16.4) — "here's where they hit it, here's where we stood." The profile drives one derived artifact worth calling out: a **suggested positioning overlay** (v1.1) — translucent fielder ghosts at spray-weighted positions, coach's judgment always on top.

### 18.5 Notes & Flags

Two note layers, both surfaced through the card's 🚩 flag:

- **`PlayerNote`** — persistent, player-scoped, cross-game: "took us deep twice last fall," "watch the delayed steal." CRUD from the card; carries author + date (provenance, as everywhere).
- **`ScorerNote` aggregation** — in-game notes (§4.4) tagged to this player, rolled up chronologically.

The flag renders only when notes exist; a count badge distinguishes one from many. In the due-batter deck, flagged players' notes surface as a banner on the card — the "you wrote this to your future self for a reason" principle.

### 18.6 In-Game Integration: The Call-Screen Underlay

The scouting payoff at the moment of maximum leverage: on the calling grid (§10.3), a toggleable **translucent underlay of the current batter's heat map** — default metric: damage (results). The coach is picking a zone *on top of the hitter's cold map*. Off by default to keep the call screen stark; one tap on the batter's name toggles it. This single feature is the answer to "why chart opponents at all," made visceral.

### 18.7 Design Language

Moved to **§23**, which is app-wide rather than scouting-scoped. Retained here as a pointer because tickets cite "§18.7 review pass" in their acceptance criteria.

---

## 19. Accounts, Onboarding, Navigation & Observation Mode

### 19.1 Auth & Sessions — the Offline Posture

- **Providers:** Sign in with Apple + Google, plus email/password. (Apple is contractually required on iOS the moment any social login is offered, so it's not optional.) **Facebook: deferred** — the coach demographic is covered by Apple/Google, and FB login adds app-review and SDK maintenance burden with no v1 payoff. Revisit only on user demand.
- **Session policy: log in once, approximately forever.** Long-lived refresh tokens with sliding expiry (90+ days, renewed on any online use). The threat model is a stolen tablet reading softball stats — calibrate accordingly.
- **The hard rule: auth never blocks the game.** Token refresh happens opportunistically online; offline, the app runs fully on the local store indefinitely — scoring, stats, scouting, everything. Expired-token-while-offline is a sync-deferral, not a lockout. A re-auth prompt may appear when connectivity returns, *after* buffered events are safely journaled. There is no screen in Diamond where "can't reach the server" prevents recording a pitch.

### 19.2 Onboarding & Team Setup

`Sign up → Create/Join team → sport → age group → zip code → done.`

- Age group + sport selects the builtin `FieldProfile` preset and `RuleSet` (§16.1) — the new coach never sees a fence-distance form unless they go looking.
- **Zip-seeded fields:** a curated, shippable dataset of parks/complexes per metro (name + field profiles). Entering a zip surfaces "fields near you" as one-tap picks at game creation. This is deliberately a *seeded dataset*, not a live API dependency — which makes the demo trivially reliable (seed the demo zips richly) and works offline. User-created field profiles append to the team's local list; a community-contributed park database is the obvious v2, gated on moderation.
- **Join flows:** team invite via link/QR (assistant coaches join with role permissions: admin/scorer/viewer). One account can belong to many teams (the coach-of-two-teams and the coach-who-moved cases), with a team switcher at the root.

### 19.3 Roster & Position Learning

Player record: **name, number, bats (L/R/S), throws** — and positions are **optional**, with a three-tier resolution when the lineup card wants a suggestion:

1. **Explicit** — positions entered on the player (ordered by preference), if any.
2. **Learned** — derived from actual game history: `LineupSet`, `PositionChange`, and `DefensiveAlignmentSet` events tell Diamond who actually plays where and how often. Surfaced as suggestions with their evidence ("6 of last 8 games at SS").
3. **Blank** — no data, no guess; the card just asks.

Explicit always outranks learned; learned suggestions never silently fill a lineup — they pre-populate, coach confirms. Lineup building itself: drag-order the batting card, tap-assign positions with conflict highlighting (two SS, nobody catching), softball DP/Flex slots rendered per `RuleSet`, saved lineup templates ("Saturday lineup," "Bracket play").

### 19.4 Navigation Skeleton

```
Auth
 └─ Team Switcher (if >1)
     └─ TEAM HOME ──────────────────────────────┐
         ├─ Games        (schedule · live · past → game detail/audit/replay)
         ├─ Stats        (§17: catalog × filters × saved bookmarks)
         ├─ The Book     (§18: own-team development view + opponent books)
         ├─ Roster       (players · lineup templates · wristband cards §10.2)
         └─ Settings     (team defaults: FieldProfile, RuleSet, capture,
                          pitch types, call zones, members & roles)
New Game → opponent (search existing book / create) → field (zip picks)
         → lineup → capture settings → [SCORE §11/§15]
Observe  → §19.5
```

Own-team scouting lives in The Book as the **development view** — same card/heat-map/spray machinery pointed inward, plus misplay and ScorerNote rollups (§13, §4.4).

### 19.5 Observation Mode — Charting Games You're Not In

The sample-size multiplier: chart a future opponent while they play *someone else* (bracket adjacency, early tournament rounds, the field next door).

- **An `ObservationSession` is a lightweight game variant:** observer team = your team; participants = Team A vs. Team B (either may be a book entry or created on the spot). Same event taxonomy, same store, same sync.
- **Relaxed integrity, by design.** Real games enforce count/out/inning coherence (§11.2's prime invariant); observation explicitly does not. You chart the PAs you care about and ignore the rest: partial innings, skipped batters, arriving in the 3rd — all fine. The projection treats observed data as *PA-level samples*, not a reconstructable game, so the "count is never wrong" machinery is simply switched off along with its bailout affordances.
- **Entry flow is the scouting subset:** pitch location (their pitcher's, if useful) → swing/take → batted-ball landing + trajectory. Outcomes optional and coarse (safe/out is one tap, or skip). Defaults tuned so one observer can plausibly chart both the hitter's spray *and* the pitcher's locations — but with capture toggles (§12.4) per session as always.
- **Provenance in the book:** observed PAs merge into the opponent's hitter cards and heat maps with a source split — `vs. us` / `observed` — filterable (§17.2 gains a source dimension) and marked on the card's denominator ("38 PA: 24 vs us, 14 observed"). Results from observed PAs feed tendency chips and profiles but are excluded from *our* pitchers'/fielders' stats, obviously, since we weren't playing.
- **Privacy default:** all charted data — played-against or observed — is private to the team. These are minors; there is no public sharing, no cross-team pooling in v1, and any future data-network feature is opt-in and its own considered design, not a growth hack.

---

## 20. Wristband Cards: Primer & PDF Print Spec

### 20.1 How These Work in the Wild (primer)

Pitcher and catcher — often the whole infield — wear playbook wristbands with a printed card behind a clear window. The coach calls a coordinate ("539"); players read row 5, column 39; the cell shows the call. Commercial and DIY systems converge on: per-pitcher cards scoped to that pitcher's arsenal, each call repeated in several randomized cells for steal-proofing, pitch colors/abbreviations for speed, and a coach-side reverse sheet organized by pitch × zone. Diamond replaces the coach sheet and the "cross off used numbers" ritual with the call screen (§10.3) — the *player-side paper card is unchanged from what kids already know.*

### 20.2 Card Anatomy

- **Pitch grid:** digit rows 1–9, column labels 10+ (as many as fit). Cell contents: pitch abbreviation + **zone glyph** — a mini 3×3 grid icon with the target cell filled (a picture, not the words "low away") + pitch-type color fill.
- **Grayscale rule:** every card must be fully readable printed black-and-white — abbrev + glyph carry 100% of the information; color is enhancement. (Coaches print at hotels.)
- **Per-pitcher scoping:** cards contain only that pitcher's arsenal, which is what makes the capacity math work.

### 20.3 Window Presets & the Capacity Solver

Presets: **Youth 1.875″ × 2.875″** (the size typically recommended for softball) · **Adult 2.5″ × 3.875″** · **Wide-Youth 2.125″ × 4.5″** · **Custom W×H**. Given window + arsenal + call zones + offense plays, Diamond solves for the max codes-per-call k that keeps cells above the minimum legible size (≥ 9pt abbrev, ≥ 0.16″ glyph), and warns before generating an eye-chart. Reference: 4 pitches × 9 zones × k=2 = 72 pitch cells fits Youth comfortably; Adult carries k=3 or a 5-pitch arsenal.

### 20.4 The Print Artifacts

All vector PDF, generated on-device, Letter/A4:

1. **Player inserts, N-up with crop marks** — identical copies for pitcher + catcher, optional full-infield set (quantity picker). Duplicate row repeated so one sheet cuts into a full team's worth.
2. **Coach backup sheet** — large-print reverse index by pitch × zone (and by offense play), listing that call's coordinates. Exists for the dead-tablet apocalypse; otherwise the app is the coach sheet.
3. **Dugout master** — the full grid at poster-ish scale for taping to the fence, optional.

### 20.5 The Offensive Card

Batters and runners wear wristbands too — so **every generated card includes an offense section**, even though Diamond v1 implements no offensive calling in-app. Print-only, by design.

- **Play library:** team-defined `PlayDef { id, label, abbrev, color }` — bunt, slap, steal, delayed steal, hit & run, take, squeeze, fake bunt, green light... entirely the team's vocabulary.
- **Letter-row grid:** offense uses letter rows ("B14") so a yelled call is *structurally* unambiguous from a pitch call ("539") — no collision possible, and defenders can't even tell which system a call belongs to without the card.
- **One combined card, everyone identical (default):** pitch grid + offense grid on the same insert means one print run, any player wears any band, and possession of a band reveals nothing about role. A separate offense-only insert is available as a layout option for small windows.
- Offense plays get k-cell repetition and decoy support identically to pitches; the capacity solver budgets both sections together.
- **Explicit non-goal:** no in-app offense call UI, no offense events, no tracking. The coach calls offense off the card by memory or the backup sheet. A `SignalCalled` event type is *reserved* in the taxonomy namespace for a future version — if offensive-call tracking ever earns its way in, it lands without a schema migration.

---

## 21. Technology Decisions

Recorded with reasoning so future contributors (human or Claude) inherit the *why*, not just the what. This section seeds `CLAUDE.md`.

### 21.1 The Stack

| Layer | Choice | One-line why |
| --- | --- | --- |
| Mobile/tablet UI | **Flutter** (Dart) | Diamond is a custom-drawn, gesture-dense canvas app — Flutter's home turf |
| On-device store | **SQLite via Drift** | offline-first is the prime directive; all projections run locally |
| Backend | **Node.js + Express** | the server is a thin auth + event-ingest + websocket relay; Node excels at exactly that shape |
| Database | **PostgreSQL** | JSONB for event payloads; the mature target for local-first sync tooling |
| Shared contract | **JSON Schema → codegen** (Dart + TS types) | one source of truth for the event taxonomy on both sides |
| Sync engine | **Spike: PowerSync vs. hand-rolled** | see §21.4 |

### 21.2 Why Flutter (and what was rejected)

Nearly nothing in Diamond is a platform widget: the call grid, zone canvas, field with draggable fielders, play chain strip, and heat maps are all custom-drawn (`CustomPaint`) with heavy gesture arbitration. Flutter renders straight to its own engine with a first-class gesture arena and one codebase across iPad/Android tablet/phone — and the classic "doesn't feel native" objection is void when there is no native-looking UI to imitate.

Rejected: **native SwiftUI + Compose** (the theoretical polish ceiling; doubles every UI ticket forever — fatal at this team size). **React Native + RN-Skia** (one real argument — end-to-end TypeScript with the backend — but its custom-canvas stack is younger and assembled from parts; the type-sharing win is captured by schema codegen instead). **Kotlin Multiplatform** (promising, too young on iOS to bet the product on).

### 21.3 Why Node (and what was rejected)

Architectural fact that dominates the choice: **all interesting compute is on-device.** Offline-first requires projections/stats/heat maps to run against the local store, so the backend reduces to auth, membership, append-only event ingest, and realtime fan-out — many cheap concurrent connections, little CPU. That's Node's best event. Team fluency and existing infra are the tiebreakers.

Rejected: **Elixir/Phoenix** (the connoisseur's realtime choice; learning curve buys nothing at this scale), **Go** (fine, unnecessary), **Rails** (deep team experience, but this service is *all* realtime — Rails' weakest limb).

### 21.4 The Sync Spike (open, timeboxed: 1 day)

The append-only, disjoint-stream event model (§12.1) makes sync a set union — the easy case. Question: adopt **PowerSync** (Flutter+Postgres local-first sync; buys resume/backpressure/schema-evolution edge cases; costs a dependency with a pricing model) or **hand-roll** (per-device sequence vectors; keeps control of the BLE transport on the roadmap; zero dependencies). Bias: hand-roll unless the spike wows, *because* the event model was designed to make this trivial and §12.6's exotic transports must be pluggable.

### 21.5 Non-negotiables (regardless of stack)

1. The event schema is defined once (JSON Schema) and generated into Dart and TypeScript — hand-written duplicates are a build failure.
2. No feature may require connectivity to record or view anything during a game (§12.6, §19.1).
3. Projections are pure functions; anything computing a stat outside the projection engine is a bug.
4. §14 acceptance plays run as fixtures in CI on both the Dart rules engine and any server-side validation.

---

## 22. Fielder Development View

The §18 machinery pointed inward at defense: per-player, per-position development cards built from data Diamond already captures — `FielderTouch` (with locations), `BallInPlay` landings, `DefensiveAlignmentSet` starts, and the misplay ledger (§13). The full §17 filter model applies (date ranges answer "is she improving since June?").

### 22.1 The Fielder Card

Per player × position (a kid who plays SS and CF gets two):

- **The chance map** — the "fielder heat map": a field-canvas rendering of every ball hit into her area of responsibility, colored by outcome — plays made (clean touches → outs/holds), misplays (amber, §13 vocabulary), and *unreached* balls that landed in her sector with no touch. Unreached is the quietly important category: it's range and positioning, invisible in any box score, and it's derivable because Diamond knows where every ball landed whether or not anyone touched it.
- **The Throw Map** — every throw the player made, rendered as origin→target arrows on the field canvas, colored by how it arrived: clean, short-hopped, high, wide (from `receivedQuality` on the receiving touch), or wild (`wild_throw`). Origin resolution: the thrower's touch `location` when captured, else the `BallInPlay`'s `retrieved ?? landing` for the first touch, else the position's standard spot. The payoff is origin-conditioned arm scouting — Mark's exact case: *routine throws are fine, but from the hole, 40% bounce* — which is invisible in every conventional stat and jumps straight off this chart. Aggregation by origin region + target base, date-range comparable like everything else on the card.
- **Range vectors** — when alignment capture was on (§16.4): start-position → touch-position arrows, giving literal measured range by direction. Left/right/in/back asymmetries jump off the chart ("she goes to her glove side beautifully and doesn't come in on anything").
- **Hands & arm rows** — misplay breakdown by type over time (booted vs. dropped vs. wild_throw trends), throw outcomes (wild-throw rate per throw), receiving (missed_catch rate at her base), tags applied/missed. Positions get relevant panels only: middle infielders see receiving/tags, outfielders see range emphasis, catchers keep their §17.3 panel.
- **Sector definition:** default responsibility sectors per position (profile-scaled), editable per team — a rec team's LF covers different ground than a travel team's. Sector edits recompute everything retroactively (projection, as always).

### 22.2 Development Use

Cards support side-by-side date-range comparison ("April vs. June"), and the `ScorerNote` rollup (incl. mental-error tags, §13.2) renders alongside the physical data. Explicit non-goal: no cross-player public leaderboards — this view exists for coaching conversations and practice planning, not shaming twelve-year-olds; sharing follows the §19.5 privacy defaults.

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

| Color | Means | Stated in |
| --- | --- | --- |
| **Amber** | uncertainty — the count is ambiguous | §12.5, §11.2 |
| **Amber** | misplay — physical, fault not yet adjudicated | §13, §15.3 |
| **Red** | error state / invalid input | — |

Amber carrying both uncertainty and misplay is deliberate: both mean *"this needs your judgment
later,"* which is one idea, and §13's whole design is that adjudication is deferrable. Per §23.1.7
neither relies on color alone — §15.3 already establishes the pattern, rendering non-clean throw
arrivals with a subtle underline rather than amber precisely because they are information, not fault.

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

### 23.5 Review

Frontend work runs through the frontend-design review pass. **"Serviceable" is the failure bar, not the
target.** Where a decision is genuinely contested, settle it on a real tablet in daylight rather than in
prose — the pattern §11.4 sets for canvas fidelity and §9 #9 sets for perspective tilt.

---
