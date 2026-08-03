# Diamond — Spec Change History

Full version history for `docs/spec.md`. The spec's own status line carries the three most recent
entries; everything else lives here. Newest first.

## v0.39

**Split duty is the design center at full capture depth.** Calling pitches is a full-attention job:
read the count and the batter, choose, yell the code, watch the glove. So is scoring a 9-3-2-5-1
double play. One person cannot do both at full capture depth, and the spec stops pretending
otherwise: the canonical full-capture arrangement is **caller + scorer** on two devices (§12.2),
with combined single-operator play kept as the supported compromise — a scorer with `pitchCalling`
off, or a caller-scorer with `battedBallDetail` off riding §11.2's ladder. §10.3 states whose
screen the calling UI is; §11.2 notes the ladder and the split are different axes. This inverts
the framing of Open Question #1's v0.2 resolution without unresolving it: Diamond is still the
calling mechanism; what changed is which arrangement the UI optimizes for.

**The caller's bundle grows to everything read at the plate.** The seam between duties falls where
attention falls: the caller's eyes are on the glove at plate-crossing for every pitch — including
the ones the scorer physically cannot locate, because contact snapped their attention to the play.
So the caller's bundle is the call, the actual location, and the actual type when the pitcher
crossed up the sign; the scorer's bundle is everything after — outcome, batted ball, fielding,
runners. Mechanically this is a sketched `PitchObserved` annotation event (`actualLocation?`,
`bounceLocation?`, `actualType?`, same mutual exclusion as `PitchThrown`) plus a `pitchObservation`
capability, paired to `PitchThrown` by time adjacency exactly as `PitchCalled` is. The schema lands
with M2's sync work, like `PitchCalled` — nothing here changed `schema/`. Granting the capability
flips the primary's location capture off, so overlap is configuration-prevented; where it happens
anyway the primary is authoritative and the audit view shows both. §12.7 gains the sequencing
consequence: two-device sync is what makes calling usable at full capture depth — the calling
feature's completion, not an enhancement.

**Ball-in-play location: both orders, and backfill at any time (§11.1).** On contact the scorer's
attention leaves the zone, so location-first is often impossible — but an implied skip on `in_play`
would throw away the times it isn't. Both orders exist: the actual-location step stays in the loop,
and the outcome row is reachable without it — score the whole play, and the loop's return offers
"record last pitch," which the scorer takes or doesn't. The offer never expires: a missing location
can be added from the pitch summary between innings or from the game stream after the game, video
up, charting every ball in play at leisure — the event inspector (§12.3) offers it on any
`PitchThrown` missing a location. All of it is one mechanism, a §6 correction to the committed
`PitchThrown` — the same post-hoc pattern as batter-action chips — so the pitch commits promptly
with `actualLocation` null, nothing is held open, and provenance shows exactly when and by whom
each location arrived.

## v0.38

**Replaced §10.1's authored call-zone rectangles with a canonical 5×5 partition of 25 cells.** The
plate and its surround are now partitioned once — the 3×3 strike-zone grid, whose outer ring is the
zone's edges (the black), plus one off-the-plate stop beyond it on each axis, corners included. Each
axis reads *off-in, in, middle, out, off-out* laterally and *off-low, low, middle, high, off-high*
vertically.

The change came out of a question the old model couldn't answer: coaches mean different things by
"down and away" depending on the count — the black on 0-0, off the corner on 1-2. The previous default
(3×3 + 4 compass chase zones) had no diagonal, so the 1-2 version had no zone to be. 25 gives it one.
Most teams will never separate the corners; the point is that the team that wants to call *too low and
too far away* doesn't have to redraw the model to do it.

Ring cells are **unbounded in extent but nominal in target**: their `bounds` run outward without limit,
because the partition cannot have a hole and containment must resolve a pitch however far off the plate,
while their centroid is placed as though the cell had the same dimensions as an in-zone cell sitting just
beyond the edge. An unbounded region has no geometric centroid, so the target has to be nominal, and
equal dimensions is both the simplest choice and the closest to what "off the plate that way" means. The
target lands half a cell out — ≈2.8″ beyond the plate edge laterally and ≈4″ past knee and armpit
vertically at 12U. The lateral figure is tight and is recorded as a starting place to revisit against
practice, not as a derived constant.

**A team's layout is now a grouping of those cells, never an independent set.** `bounds` is derived
from the grouping rather than authored, which makes overlapping zones and uncovered gaps
unrepresentable instead of merely invalid — and containment classification (§17.4) depends on exactly
that, since freeform intent and observation mode (§19.5) both need any point to resolve to one zone. A
10U team groups a whole edge into one "chase high"; a 14U team leaves those cells separate.

**Zones are batter-relative; coordinates stay absolute.** §10.1's vocabulary was already relative
("Up-In", "Low-Away") while `ZoneCoord` is absolute in the catcher's view (§3.1), and nothing said how
one became the other. The wristband settles it: a code has to mean one thing to the pitcher reading it,
so a zone is named from the batter's point of view and mirrored to an absolute `intendedLocation` when
the pitch is written. `intendedZoneId` then aggregates across a lineup without mixing inside-to-a-lefty
with away-to-a-righty, which §17.4's command rubric depends on. Nothing mirrors on screen: the call grid is
drawn on the entry canvas itself, so the geometry stays absolute and fixed and only the *label*
resolves — "In" sits at negative x for a righty, positive for a lefty — which preserves §11.4's
never-mirror rule rather than excepting it.

**The call grid lives on the entry canvas, not beside it.** §11.4 said both: line 481 had the zone rect
carrying the grid, while the canvas-extents table and two notes below it described a side-by-side
layout competing for horizontal room. The single-surface reading wins, and v0.38 is why — the canvas
already spans x ∈ [±4.0] and y ∈ [−1.05, 1.5], which is exactly where the 16 ring cells sit (their
nominal targets are at x ≈ ±1.33), so the 3×3 lands inside the zone rect and the ring fills the canvas
around it. The coach calls and records on the same picture, and the width the side-by-side layout would
have spent on a second grid is freed for the screen's other furniture. The stale side-by-side notes are
corrected.

Grouping is also what keeps intent comparable over time. A player's history follows them (§22) across
age groups whose vocabularies differ, and because every layout groups the same 25 cells, any two roll
up to a common frame. Independently authored rectangles would not.

**The callable set is per pitch type, and entirely the coach's.** Each type carries its own subset of
the team's zones. Diamond has no opinion about which locations suit which pitch — a high drop and a low
rise are real calls — so every cell is available to every type, the default is all-callable, and
narrowing is always the coach's act rather than the app's inference. The matrix is sparse in practice,
which is what keeps a six-pitch arsenal printable (cell count is the sum over types of that type's zone
count × k, not the cross product), but nothing enforces sparsity. The call screen offers exactly what
the **active card** can express and never more: a code the coach can yell must be a code the pitcher
can look up, so editing a type's zones invalidates the card and requires a regenerate (§10.2).

**Resolves Open Question #7.** The coach picks a zone off the grid and there is no sub-zone nudge on
the call side. A nudged coordinate has no code — §10.2 keys codes to (pitch type × call zone) — so
refining intent past the zone would record a target the pitcher was never told and then grade them
against it in §17.4. Situational variation in what a zone *means* is read off `actualLocation` against
the count instead. Freeform capture remains for contexts with no call at all: solo scoring, verbal
calling, observation mode.

**§10.2 records that k is per call, not per card** — as direction, not as implemented behavior. Calls
are not thrown equally often, and a code's job is to keep the frequent ones from becoming recognizable,
so a call's code count should follow how often it is expected to be called; uniform k stays the starting
default. Card size therefore reads as the sum over calls of their code counts, and the three-digit format
caps a card at 9 x 90 = 810 cells, which the generator must enforce rather than silently emitting
four-digit codes. Allocation belongs with wristband setup, which has no ticket yet — hence recording the
direction here so it is not rediscovered.

**§11.4 states what the grid draws, and when.** The 3x3 strike zone renders at all times, on the
calling surface and the actual-location surface alike, because it is the frame every location is read
against. The sixteen cells around it are drawn only while a pitch is being called and only where that
pitch can actually be called, since they are the available choices; on the actual-location surface they
are not drawn at all and are merely implied, containment still resolving any point into exactly one of
them (§17.4). A callable zone draws as one swatch the size of a strike-zone cell, centered on its
target, never one mark per member cell — a grouped zone is one call with one code, and painting its
cells separately shows several targets where there is one.

**§10.3** now states that type precedes zone because the vocabulary depends on the type, and that the
grid's geometry is fixed and never re-flows between types — only which cells are callable changes.
Muscle memory across 120 pitches is worth more than larger targets.

Two §10.3 corrections follow from the above. The type row is **no longer color-coded**: §23.1.2 allows
one accent live at a time and it belongs to the selected type (§23.1.3), so per-type color was earlier
guidance that §23's precedence rule makes a defect rather than a competing option. Color-coding pitch
types remains plausible on a **review** surface, where it is categorical encoding in a chart rather
than a second accent and §23.4's different rules apply; it is recorded as such so it is not re-added to
the calling screen. And the **tap-and-hold chase gesture is removed**: with 25 callable cells every
off-plate location is directly tappable, a hold could only ever resolve to a cell that is already
callable, and it was undefined on the center cell, which has no outward direction.

No event-schema change: only `intendedZoneId` (a string) reaches `pitch_thrown.schema.json`;
`CallZone`'s shape is team configuration, so no codegen, fixtures, or regeneration are involved.

This version also repairs a protocol lapse: v0.37's content landed in the spec, and its full entry
landed here, but the spec's own header and status line were never updated and still read v0.36. The
status line now carries v0.38 / v0.37 / v0.36.

## v0.37

**Promoted design language to its own top-level section, §23**, and left §18.7 as a pointer stub. The
old placement was scouting-scoped in name only — DIA-005 and DIA-011 both specify a "§18.7 review pass"
for the pitch entry canvas, a §11 surface — so the section is now stated to be app-wide. Appended rather
than inserted: §23 follows §22 as this document has always grown (§22, a UI/projection section, already
sits after §21's technology decisions), which avoids renumbering §19–§22 and breaking `CLAUDE.md`'s
§21.5 non-negotiables, DIA-002's §21.5(1), and every reference to §19.5, §16.x and §22.1. The stub keeps
existing ticket acceptance criteria resolving correctly.

§23 carries a **precedence rule**: it supersedes design guidance stated earlier in the spec, and where
earlier text conflicts, the earlier text is a defect. The boundary is narrow and stated explicitly —
§23 governs design language, not derived geometry (§11.4), data-model rules (§1–§7), or a surface's own
composition. A design pass does not relitigate a computed value; if §23 appears to contradict one, §23
is wrong.

New: **§23.2 semantic reservations** (amber = uncertainty *and* misplay — one idea, "this needs judgment
later"; red = error), pulled out of the old principle 2 because they are load-bearing across §12.5, §13
and §15.3 and were too easy to miss inside a list item. New principle **7, "never color alone,"** which
§15.3's underline convention was already following without it being written down.

New: **§23.3 color contexts** — brand baseline, own-team accent, opponent accent, with one accent slot
between them, so "one accent system" is preserved rather than weakened: what is contextual is the
accent's value, not how many are live. The opponent accent is a drill-in condition rather than a game
state (a Tuesday scouting report themes as Saturday's live game does), and deliberately does not apply
to schedules or any list of several opponents, where eight accents at once destroys the signal by making
it constant. Color is stored as data and derived at read time per Core Principle #3; derivation owns
contrast in both modes since seeds are arbitrary; unset opponent colors fall back rather than being
invented.

New: **§23.4**, generalizing §11.4's per-surface fidelity split — entry surfaces are used at speed in
sunlight and spend nothing on decoration; review surfaces are used at leisure and are where the product
is judged.

Opened **Open Question #10**: team colors that collide with the reserved amber/red. Three resolutions,
all with real costs; shelved for a field test. Blocks the picker, not DIA-012's plumbing.

## v0.36

**Built the batter silhouette** as a derived, first-class part of the entry canvas (§11.4), reversing the earlier decision to keep it behind a debug flag as a calibration instrument. It is a location cue first: a coach picks a call and reads an actual against a body, not against an empty rectangle. It ships **off by default** — the geometry is right but the *drawing* is not yet convincing, so the figure is hidden pending DIA-013 and the canvas carries no occupied-side cue in the meantime. Visibility is a parameter rather than a temporary constant, since a future practice state (bullpens with no batter) wants the same switch driven by a user setting.

The objection that kept it off was real and is **answered rather than overridden**. `y ∈ [0,1]` is *this batter's* zone, so a silhouette drawn at one fixed height is honest only for a batter of that height and would visibly contradict the zone rect for a tall or short kid — on the surface a coach looks at 120 times a game. The fix is to derive her from the zone profile: her knee is `y = 0` and her armpit is `y = 1`, definitionally the zone's own edges, so she tracks the rect for every batter by construction and cannot drift from it. Stature follows from the profile (58″ at 12U via §3.1's canonical pairing) and everything else is human proportion as a fraction of stature. This is the escape clause the earlier text already anticipated — "driven from a batter-height parameter so it cannot drift from the zone it illustrates" — applied to the entry canvas rather than only to review surfaces.

**She is the only occupied-side cue.** The batter's-box fill (frontal) and shading (top-down) are dropped from both planes: two competing indicators for one fact is worse than one, and the boxes remain the reference frame for location on either side of the plate regardless of who is up. `x` stays absolute and the canvas still never mirrors — only the silhouette moves. She renders in the **frontal plane only**, since her job is the vertical knee-to-armpit read and the top-down plane has no axis for it, and she takes **no pointer events**: a pitch may be recorded anywhere on the canvas including at her body, so a silhouette that swallowed taps would make the region it occupies uncapturable. Her head is frame-cut at upper-face level by the +1.5 top, which is that trim working as designed.

Also recorded in §3.1 as planned, uncontested work: **batter height becomes settable, and the default profile is chosen by sport and age level** rather than hardcoded to 12U fastpitch. Everything derived from a profile is already expressed as a function of its two numbers so that lands without a second geometry pass.

## v0.35

Made **`BounceCoord.depth` optional** (§3.3). §11.1 had always said that skipping the second placement records "in the dirt, depth unknown", but nothing in the schema could express it: `depth` was required, `PitchThrown` has no bounced flag, and so the one honest encoding was to drop the bounce entirely and lose an observation the coach actually made. The hinge is reached by a release in the dirt band, which always yields a lateral position, so `x` stays required and `depth` alone becomes absent. **Absent is never 0** — `depth: 0` means the ball hit the plate's front edge, which is a measurement, not a gap. Both consumers that don't need depth already read fine without it: §4.1's conventional `y_ground` coordinate needs only `x`, and §17.4 needs only that a bounce happened.

Corrected §11.4's **top-down plane geometry**. The section's own constraints — same px-per-x as the frontal plane, and isotropic — leave the depth range no freedom at all: sharing px-per-x fixes px-per-inch, isotropy then makes the shared drawing rect fix how many inches fit vertically, and the result is exactly the frontal plane's own vertical extent in inches, **61.2″ = 5.10 ft** at 12U. The quoted −1 ft…+5 ft (72″, ≈ 0.94 : 1) assumed a taller rect than the frontal plane occupies and was never achievable alongside parity; it also predated v0.25's correction that a bounce is commonly *before the catcher*, not only out front, which argues for more catcher-side room rather than the 1 ft it allowed. Only the anchor is genuinely free, and it splits the range at **−2.5 ft … +2.60 ft**: the aft extent is fixed at 30″ in inches (the plate's whole 17″ pentagon plus 13″ behind it) because the plate is 17″ for every batter, so the profile-dependent part of the range is absorbed by the fore side. Consequence worth stating: the range moves with the batter's zone height, since the rect's aspect does — the rect is the same rect, only what fills it changes.

Dropped the **catcher position** from the top-down plane. §11.4 had called for one, but there is no rulebook position for a catcher, so any mark is invented — and rendered as an indicative arc it read as an unexplained shadow rather than a person, which is worse than absent. Nothing else needs to establish which way is behind: the plate's point does it, in both planes, because both are the catcher's view looking out at the field — which is also why the depth labels are unsigned and the `depth = 0` gridline is drawn exactly like every other gridline rather than emphasised. Also stated explicitly that the plane draws **inner and front box lines, not back or outer** — the same rule the frontal plane follows. Whether the front line is *visible* is a `RuleSet` consequence rather than a special case: baseball's box terminates 2.29 ft out front, inside the canvas, while fastpitch's reaches 4.0 ft and runs off the top edge. Drawing only the inner line left baseball's chalk stopping 0.31 ft short of the frame with nothing to say why.

Dropped the **0–2 ft / 2–4 ft / 4 ft+ depth bands** in the same breath. They assumed the un-achievable range (4 ft+ is off-canvas at +2.60), and `depth` is a continuous float that is never bucketed in storage regardless (§3.3), so the buckets were a rendering convention standing in for an axis. Replaced by a gridline every foot, labelled unsigned ("1 ft", "2 ft") on both sides — the plate sits between them, so the label does not have to carry direction.

## v0.34

Promoted §11.4's **azimuth 0** from an incidental camera parameter to a stated constraint. An off-axis camera projects the 17″ edge's two corners at different distances from centre, so `x = ±1` stops mapping symmetrically onto it and the exact-registration requirement — which the section states and the geometry tests assert — breaks. That is why the plate renders as a symmetric trapezoid with no tilt despite broadcast reference footage being shot off-axis. The reason had lived only in a code comment; the spec read as though the value were arbitrary. Also opened **Open Question #9**: should the ground perspective tilt per batter handedness? For it, the off-axis look reads more naturally and the batter does stand on one side; against it, registration breaks and the zone grid stays orthographic regardless, so only the ground furniture would tilt and risk reading as a mismatch with the grid above it. Shelved — not required for v1 or Milestone 1, and explicitly out of scope for DIA-011.

## v0.33

Trimmed §11.4's top extent from +1.80 to **+1.5** — half a zone height above the zone, ≈ 12″ over the letters, upper-face level at 12U. Above that nothing is learned: a foot over the head and two inches over the head are the same observation, and §17.4 buckets both as uncompetitive-high, so those pitches stay recordable but land unresolved on the top edge. Shoulder height (y ≈ 1.31) stays resolved, since an elevated fastball is a location rather than a miss. Canvas becomes ≈ 68″ × 61″ (≈ 1.11 : 1) and gains vertical room for the count HUD and outcome row. Also added an explicit note on **which canvas dimension binds**, because the earlier "widening is free in tap precision" claim was true only in the height-bound case: height-bound, zone px = panelHeight / verticalExtent and lateral range does not enter; width-bound (a width budget so the call column fits) zone px = panelWidth × 2 / lateralExtent and vertical extent does not enter. Worked at 1180 × 760 leaving ~450 for calls, ±4.0 with the top at +1.5 gives a 730 × 657 panel and a 182 × 258 zone versus 189 × 267 under the old ±1.9 / +1.80 frame — so reaching the batter and the full box cost ≈ 4% of zone size and ~400 px of width rather than tap precision.

## v0.32

Widened §11.4's lateral range from ±1.9 to **±4.0**, and changed its justification. Reaching the batter's-box chalk was never the requirement: a pitch may be recorded anywhere on the canvas, including at the batter, and the silhouette lays over part of it rather than the frame being sized to exclude her. A 12U stance puts her body centre ≈ 26–30″ off plate centre (x ≈ 3.1–3.5, spanning x ∈ [2.4, 4.3]), so ±4.0 leaves capture room on both sides. Widening costs nothing in tap precision — the canvas is height-limited on a tablet, so the zone's on-screen size is fixed by the vertical scale and lateral range only adds pixels beside it (*over-stated; corrected in v0.33 — this holds only when height binds, and the side-by-side layout is width-bound, where widening is exactly what costs*); what it spends is horizontal room competing with the call grid, which is why it stops short of ±6.0 (where the whole 36″ box would fit, but its outer ~20″ is chalk nobody stands in). Consequences: the canvas becomes ≈ 68″ × 68″ (≈ 1 : 1) instead of 2.1 : 1 portrait; nothing clips laterally, so the chalk band reads as a line instead of a clipped wedge and the visible inner run grows to ≈ 80″ of the 84″ box (y ∈ [−1.05, −0.363], bounded by the canvas bottom rather than the frame edge) with ≈ 25″ of the front line; the top-down plane's −1 ft…+5 ft depth range now renders at ≈ 0.94 : 1. Also: the ground-line boundary keeps the fade's inherent tonal step and **drops the drawn full-width rule** (an explicit line read as an arbitrary graphic; revisit when the hinge gives the boundary interaction weight); the shadow batter is stated to be paint that takes no pointer events, since a silhouette swallowing taps would make the region it occupies uncapturable; and the plate's on-screen depth is corrected from 0.153 to **0.152** y-units (816/5352 = 0.15247, and 0.215 × 17/24 = 0.15229 — both round to 0.152), caught by a geometry test computing from the canonical inputs rather than copying the prose.

## v0.31

Replaced §11.4's `y = −0.45` scenery cap with a distance fade. The cap had been protecting grid legibility against a busy backdrop, which a fade protects without truncating the ground furniture drawn on the receding plane; ground in front of the plate is where a bounced pitch lands and is drawn as dirt to its natural extent. Consequences: the no-chalk-above-the-ground-line rule is withdrawn, both the inner and front batter's-box chalk lines render (≈ 64″ of an 84″ box visible at the default camera rather than ≈ 24.5″), and Open Question #8 closes. Also records that the drawn ground plane above the line is geometrically invertible to a bounce depth and is deliberately not read that way — taps above `y_ground` are airborne, and depth comes only through the hinge.

## v0.30

Moved the version history out of the spec's status line into this file; the status line now carries the three most recent entries only.

## v0.29

A wording pass over §3.1, §11.1, §11.4 and §18.7 — no numbers or rules changed; rationale, correction history, and comparisons against the current build are removed, and remaining judgment calls point at Open Question #8 or the review that settled them.

## v0.28

Resolves a conflict between v0.26's chalk rule and its own no-chalk-above-the-ground-line rule: the batter's boxes lie mostly forward of the plate and therefore project above the ground line in *every* camera, so only the inner line renders and it clips at `y_ground`; box legibility joins the scenery cap as a field-test question (§9 #8, §11.4).

## v0.27

Records the pitch-canvas scenery cap as an open question rather than a settled figure — it is the one value in §11.4's geometry that is chosen rather than derived (§9 #8, §11.4).

## v0.26

Corrects the v0.25 foreshortening formula (`H/(d−17″)`, not `H/(d+17″)`; 0.215 at the default camera, not 0.19), replaces the applied ratio with a real pinhole projection, states the camera constraints as coupled, splits drawn ground from the hinge trigger and caps scenery by a `y` bound rather than by feet, fixes canonical zone-height inputs so derived values and test tolerances agree, and specifies the chalk convention (§3.1, §11.1, §11.4).

## v0.25

Makes the pitch canvas's vertical geometry derived rather than eyeballed: the ground plane is a computed `ZoneCoord` value, the plate is foreshortened by a stated virtual-camera ratio, the zone rect and call grid stay orthographic while ground furniture takes perspective, the lateral range widens to reach the batter's-box chalk, and batter's-box dimensions route through `RuleSet` (§3.1, §11.1, §11.4, §18.7).

## v0.24

Records the canvas fidelity question as an open golden-test decision rather than a settled directive (§11.4).

## v0.23

Specified the pitch canvas composition for both planes — plate anchor, batter's boxes, lateral registration, dirt band (§11.4).

## v0.22

Derives chase intent from zone position instead of storing a flag (§10.1, §17.4).

## v0.21

Unified command classification on call-zone resolution (freeform taps resolve to the containing zone, so one rubric covers both producers) and replaced "waste" terminology (§10.1, §17.4).

## v0.20

Replaced miss-distance magnitude with command classification (executed / competitive miss / uncompetitive, plus miss direction) (§17.4).

## v0.19

Adds `BounceCoord` (§3.3) and `bounceLocation` on `PitchThrown` (§4.1) for pitches that hit the dirt before reaching the plate, captured via the dirt-band hinge interaction (§11.1).

## v0.18

Allows `intendedLocation` to be captured either via the call-zone grid (centroid, `intendedZoneId` set) or as a freeform tap (`intendedZoneId` null) — see §10.1.

## v0.17

Adds `EarnedRunOverride`/`RbiOverride`, a narrow scorer-judgment exception to §13.3's earned-run/RBI derivation (§13.5).

## v0.16

Specified two-tier (per-pitch / aggregate) back-inference semantics for `CountCorrection` checkpoints (§12.5).

## v0.15

Added per-pitch batter actions (showed bunt, pulled back, slap, fake slap, slash) to PitchThrown (§4.1).
