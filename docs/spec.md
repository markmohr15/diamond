# Diamond — Event Taxonomy & Pitch Entry Spec (v0.11)

**Status:** Draft for review — v0.11 adds Technology Decisions (§21): the stack, the reasoning, and the decisions deferred to spikes
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

- Normalized to the *batter's* zone, not absolute inches — so heat maps compare across batters of different heights. The zone rectangle is x ∈ [-1, 1], y ∈ [0, 1]; values outside that range are valid and represent pitches out of the zone (e.g., y = -0.4 is in the dirt, x = 1.8 is well outside).
- **Handedness note:** x is stored in absolute terms (negative = third-base side, positive = first-base side, catcher's view). Projections flip to "inside/outside" using the batter's handedness at render time. Storing absolute and deriving relative avoids corruption when a switch-hitter's side is corrected later.
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
                                  //   location capture is ON (§12.4); null = not captured
  velocity?: number;              // mph, optional (radar gun)
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
- **Intended vs. actual is the killer feature.** `intendedLocation` + `actualLocation` gives you a *command* metric no consumer app has: miss distance per pitch type, per pitcher, over time. `intendedType` vs `actualType` catches crossed-up signals and "she can't land the drop ball today."
- Both intended fields are optional so scoring doesn't stall when nobody's calling pitches (opponent scouting mode: you don't know their calls).
- Non-swing dead-ball weirdness (catcher's interference, batter interference on the swing) is handled by follow-up events, not more outcome variants.

### 4.2 Batted Ball Events

```typescript
interface BallInPlay {
  pitchEventId: string;          // links to the PitchThrown
  fair: boolean;                 // foul balls with coordinates welcome (§3.2)
  trajectory: 'ground' | 'line' | 'fly' | 'popup' | 'bunt';
  contactQuality?: 'weak' | 'average' | 'hard';   // scorer judgment, optional
  landing: FieldCoord;           // where it landed / was first touched
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
  | DefensiveAlignmentSet  // fielder starting coordinates; sticky until changed (§16.4)
  | InningHalfStart    // derived state checkpoint boundary
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
|---|---|
| Live scorebook / box score | all events |
| Pitch location heat maps (by pitcher, type, count, batter side) | PitchThrown |
| **Command charts** (intended vs. actual miss vectors) | PitchThrown |
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

---

## 10. Pitch Calling & Wristband Codes

Diamond replaces the laminated call sheet: the coach taps the call, Diamond displays the three-digit code, the coach yells it, the pitcher (and catcher) look it up on their wristband cards. The intended-pitch data is captured as a byproduct of calling the game — zero added workload.

### 10.1 Call Zones

Coaches call *zones*, not coordinates. Each team configures a **call-zone layout**:

```typescript
interface CallZone {
  id: string;
  label: string;          // "Up-In", "Low-Away", "Waste-Up", ...
  centroid: ZoneCoord;    // canonical target for command-chart math
  bounds: ZoneRect;       // hit region on the calling grid
}
```

- Default layout: 3×3 in-zone grid + 4 out-of-zone "waste" spots (up, down, in, out). Teams can simplify (5-spot: in/out/up/down/middle) or extend.
- `PitchThrown.intendedLocation` stores the zone's `centroid`; a new optional field `intendedZoneId` stores the zone identity so projections can aggregate by call zone directly. Miss distance = actual − centroid.

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
- **Grid coordinates, randomized contents** (revised v0.10 after studying real-world systems). Cards are read as coordinates — first digit = row (1–9), remaining digits = column label — because lookup must be O(1): a ten-year-old finds row 5, column 39 in two seconds, while scanning a flat list of random numbers between pitches is misery. The security lives in the *contents*: cell assignments are randomized per card, the same call occupies its k cells at unrelated coordinates, and digits carry zero pitch meaning. Letter rows are a supported card option ("C-14") for teams that prefer them.
- **Rotation:** cards regenerate per opponent (or on demand mid-tournament if the coach suspects a leak). Old cards are retained read-only — historical `PitchThrown` events don't reference codes at all (only type + zone), so rotation never touches game data.
- **Print/export:** Diamond generates a PDF of wristband inserts — the standard grid sized for common wristband window dimensions (configurable), pitcher and catcher copies, plus a large-print dugout backup. Kill feature for adoption: coaches currently make these in Excel and hate it.
- **Decoys (optional toggle):** pad the card with codes that map to no call, and let the coach yell a decoy with a tap-and-hold. v1.1 candidate; card schema supports it (`CodeEntry.pitchTypeId: null`).

### 10.3 Calling UI

The call screen is two taps: **pitch type** (button row, team's configured arsenal, color-coded) then **zone** (the grid). On the second tap, the code renders **huge** — 120pt+, readable at arm's length in sunlight — with the call echoed underneath in small text ("Rise · Up-In · #539"). A re-roll gesture (swipe the code) picks a different code for the same call without re-tapping. Tap-and-hold a zone = "ball, don't care where" waste pitch shortcut.

The pending call persists on screen until the pitch result is entered, then the flow returns to the call screen for the next pitch. Shake-off reality: if the coach changes the call, tapping a new type/zone simply replaces the pending call — nothing is committed to the event stream until the pitch actually happens.

## 11. Per-Pitch Entry Flow

The loop that runs 120+ times a game. Tap budget per pitch, full mode: **4** (type, zone → code; actual location; outcome confirm).

### 11.1 The Loop

```
┌─► [CALL]    tap type → tap zone → CODE DISPLAYED (yell it)
│   [PITCH HAPPENS]
│   [ACTUAL]  one tap on the zone canvas = actualLocation
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
- **Fielding sequence entry:** after the landing tap, a position diamond appears; the coach taps positions in order (6 → 4 → 3), long-press a position for the error variants. Runner resolution screen shows the bases with drag-to-advance / drag-to-out. This is the deepest sub-flow and gets its own spec section (v0.3) with every GameChanger-broken play as a test case.

### 11.2 The Mode Ladder (degradation under pressure)

| Mode | Captures | When |
|---|---|---|
| **Full** (default) | call + actual + outcome + batted ball detail | normal game flow |
| **Scorer** | actual + outcome (skip call — e.g., opponent at bat, or catcher calling her own game) | opponent half-innings, tempo spikes |
| **Bailout** | outcome only — one giant BALL / STRIKE / IN-PLAY row | chaos: conferences, injuries, arguments |

- Mode is *per-tap-sequence*, not a settings toggle: the actual-location canvas has a persistent "skip location" affordance, and a two-finger swipe drops to bailout for the current pitch. The ladder exists to protect the one invariant that matters: **the count and game state are never wrong.** Heat maps survive 15% missing locations; a scorebook that disagrees with the umpire kills the app's credibility permanently.
- Opponent half-innings default to Scorer mode with the batted-ball flow emphasized (their spray data is the scouting payload) — no calling UI shown.

### 11.3 State the Loop Manages Automatically

Batter advance (from lineup projection), count reset, inning flip, pitcher's pitch count, forced-runner suggestions on walks (auto-generate `RunnerAdvance` events, coach confirms), courtesy-runner prompts when the pitcher/catcher reaches base (RuleSet-gated), and D3K arming (uncaught third strike with first base open / two outs → Diamond prompts the runner resolution instead of assuming the out). Undo is always one tap, top-level, unlimited depth (§6).

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
- Projections handle sparse data by design: heat maps aggregate whatever locations exist; command charts require both intended and actual and simply show coverage ("41 of 87 pitches charted") so nobody mistakes sparse for complete.

### 12.5 The `unknown` Outcome & Count Checkpoints

Reality: the scorer looks up and the count changed. Two mechanisms keep the book honest:

- **`outcome: 'unknown'`** — "a pitch happened, I don't know what it was." Keeps pitch count accurate but leaves the ball/strike count ambiguous, so the projection marks derived count **uncertain** (rendered with a visual flag, e.g., amber count display).
- **`CountCorrection { balls, strikes }`** — an authoritative checkpoint: "the scoreboard says 2-1, make it so." Entered via long-press on the count display → set the count → done. The projection treats it as an override from that point forward and clears the uncertainty flag. Retroactively, unknown pitches between the last known state and the checkpoint can be inferred (2 unknowns + checkpoint at 2-1 from 1-0 = one ball, one strike) — inferred outcomes are marked as such and excluded from pitch-quality analytics, included in pitch counts.
- This is deliberately a narrow exception to §5's "derive everything": corrections of *reality-capture gaps* get checkpoint events (`CountCorrection` now; `BaseStateCorrection` reserved for the same pattern if field testing demands it). The projection remains a pure fold — checkpoints are just events with override semantics.

### 12.6 Transport Ladder

The sync engine is **transport-agnostic**: its only job is "exchange event batches I have that you don't" (per-device sequence vectors make gap detection trivial). Transports are pluggable pipes beneath it, attempted in order:

| Transport | When | Notes |
|---|---|---|
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
|---|---|---|
| **Physical record** | FielderTouch types, RunnerAdvance/Out links | dropped, booted, wild_throw; "runner took third *on that throw*" |
| **Judgment** | one flag: `ordinaryEffort` on misplay touches | "she should have had it" vs. "diving attempt, no play" |
| **Official scoring** | projection output, never entered | E5, hit vs. E, earned vs. unearned runs, 6-3 |

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

After the landing tap + trajectory (§11.1), the play canvas shows the field with fielders at their positions and the ball at its landing point.

- **Tap a fielder** = that fielder touched the ball (`fielded`/`caught` inferred from trajectory + whether the landing was marked caught).
- **Drag the ball** from the current fielder to another = a throw; the receiver gets `received_throw`.
- **Drag a runner** to a base = advance; **drag a runner to an out affordance at a base** (or flick toward the dugout) = out, with `how` inferred from context (force vs. tag from the base state, fly out from a caught ball) and confirmable.
- Runner advance arrows auto-attribute to the most recent touch/misplay; tap an arrow to re-attribute.

### 15.2 The Play Chain Strip

As the sequence builds, a horizontal strip above the canvas renders it as nodes: **⚾ → 6 → 4 → 3**, with runner consequences hanging beneath the touch that caused them. This strip is the play's visible event log — and every node is a live control.

### 15.3 The Modifier Chip — "something else happened here"

Every node in the chain carries a small **"+" chip**. Tapping it opens a compact radial/sheet menu scoped to what makes sense *at that point in the sequence*:

- **On a touch node:** the misplay set — `dropped`, `booted`, `bobbled`, `wild_throw` (converts the following drag's meaning), `missed_catch`, `tag_missed`. Selecting one recolors the node (misplays render amber) and, when the play commits, triggers the `ordinaryEffort` inference or prompt (§13.2).
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

Resolution order at `GameStart`: **per-game override → team default → builtin(sport, age group)**. A team sets its default once; a coach at an unfamiliar tournament field adjusts five numbers (or picks a saved field — profiles for real parks are reusable and nameable) and everything downstream is correct.

**Builtin presets** — draft values, to be finalized with real sanctioning-body specs before ship (⚠ verify):

| Preset | Fence (line/gap/CF) | Base path | Pitching |
|---|---|---|---|
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
- **Opponent**, **home/away**, **game type** (league/tournament/scrimmage — scrimmages excludable by default, toggleable)

**Split filters** (select events within games — the Diamond-only tier):
- vs. batter/pitcher handedness · by count state (ahead/behind/even/2-strike/3-ball) · by pitch type · runners on / RISP / bases empty · by inning · times-through-the-order · by call zone

**Saved filters:** any combination is nameable and pinnable ("Fall vs. Elite teams", "2-strike ABs"). A saved filter + a stat view is a bookmark — the coach's dashboard is just pinned bookmarks.

### 17.3 The Catalog

**Tier 1 — table stakes (GC parity, correctly computed):**

| Domain | Stats |
|---|---|
| Batting | G, PA, AB, H, 2B, 3B, HR, R, RBI, BB, HBP, K, SB, CS, SAC, SF, AVG, OBP, SLG, OPS |
| Pitching | G, GS, IP, BF, H, R, **ER (per §13.3 — actually right)**, BB, HBP, K, W/L/SV, ERA, WHIP, K/BB, pitch count, pitches/inning |
| Fielding | PO, A, E, FPCT, DP |
| Catching | SB allowed, CS, CS%, PB |

Softball rendering nuances via `RuleSet`: 7-inning ERA normalization, tie games, run-rule finals annotated.

**Tier 2 — pitch-level (impossible without Diamond's data):**

| Domain | Stats |
|---|---|
| Plate discipline | swing %, chase % (swings out of zone), whiff %, contact %, first-pitch swing %, pitches/PA |
| Batted ball | GB/LD/FB/PU %, hard-hit % (contactQuality), avg distance, pull/center/oppo %, foul-ball direction tendencies |
| Pitcher command | strike %, first-pitch strike %, **miss distance by pitch type (intended vs. actual)**, zone % by count, called-strike edge % |
| Pitch mix | usage % by type, by count, by batter side; velocity if captured |
| Catcher | blocks per D3K opportunity, D3K conversion against |
| Defense | misplays (charged-or-not, §13), range (landing − start, §16.4) |

Tier 2 stats degrade gracefully with capture gaps (§12.4): each shows its denominator coverage ("41 of 87 pitches located") so sparse never masquerades as complete.

### 17.4 Performance Model

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

### 18.7 Design Language (the "lacks class" mandate)

Applies to every stat and scouting surface. Principles, enforceable in review:

1. **Data-ink first.** No card chrome, gradients, or mascot clip-art competing with numbers. Generous whitespace; tabular numerals; a real typographic hierarchy (stat values large, labels small and quiet).
2. **One accent system.** Team color as the single accent; heat maps get one perceptually-uniform colormap (not red-green rainbow); semantic amber/red reserved for uncertainty and misplays.
3. **Glanceable at arm's length in sunlight.** The dugout is the design environment: high contrast, big touch targets, no hover-dependent anything, dark mode for night games.
4. **Numbers carry their honesty.** Denominators and coverage always visible (§17.3); no stat rendered without its n.
5. **Motion is meaning.** Transitions only where they explain state change (deck advancing, count updating) — never decorative.

Build note: frontend work runs through the frontend-design review pass; "serviceable" is the failure bar, not the target.

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
|---|---|---|
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
