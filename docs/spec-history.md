# Diamond — Spec Change History

Full version history for `docs/spec.md`. The spec's own status line carries the three most recent
entries; everything else lives here. Newest first.

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
