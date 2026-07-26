# Diamond — Spec Change History

Full version history for `docs/spec.md`. The spec's own status line carries the three most recent
entries; everything else lives here. Newest first.

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
