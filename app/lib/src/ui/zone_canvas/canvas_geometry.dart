/// Pitch-canvas geometry (§3.1, §11.4).
///
/// The frontal plane is a scale drawing: every value here is a consequence of
/// §3.1's normalization plus one pinhole ground projection, not a layout
/// preference. Nothing in this file is a tuned literal except where a comment
/// says so explicitly (the canvas extents and the ground fade).
///
/// Rounded figures in the spec's prose are display, not source (§3.1) — this
/// file computes from the canonical inputs, and tests assert against those
/// computations rather than against text like "−0.65".
library;

import 'dart:math' as math;

/// Strike-zone rectangle bounds (§3.1): x ∈ [-1, 1], y ∈ [0, 1].
const double zoneMinX = -1;
const double zoneMaxX = 1;
const double zoneMinY = 0;
const double zoneMaxY = 1;

/// Home plate: 17″ across the edge facing the pitcher, and 17″ deep from that
/// edge to the point (8.5″ of straight side, then the converging faces).
const double plateWidthInches = 17;
const double plateHalfWidthInches = plateWidthInches / 2; // = 1 x-unit, always
const double plateDepthInches = 17;
const double plateSideInches = plateWidthInches / 2;

/// Vertical zone geometry for one batter. `y` normalizes against *this*
/// batter's zone height (§3.1), so both [groundY] and [axisScaleRatio] move
/// per batter — neither may ever become a constant.
///
/// Until per-batter heights land, [canonical12U] is the shipped placeholder.
/// Planned, not contested (§3.1): batter height becomes settable, and the
/// default profile is chosen by **sport and age level** rather than being
/// hardcoded to 12U fastpitch. Everything derived from a profile — `y_ground`,
/// the axis ratio, the top-down depth extent, the batter silhouette — is a
/// function of these two numbers precisely so that drops in without a second
/// geometry pass.
class ZoneProfile {
  const ZoneProfile({required this.bottomInches, required this.topInches});

  /// Height of the zone's bottom edge above the ground — knee top.
  final double bottomInches;

  /// Height of the zone's top edge above the ground — armpit/sternum.
  final double topInches;

  /// §3.1's canonical 12U fastpitch profile: ~58″ athlete, 15.5″–39.5″, which
  /// is a 24″ zone height. These two numbers are the source for `y_ground`
  /// (−0.6458) and the axis ratio (0.354); the spec's rounded quotes of both
  /// are derived from here, never the other way round.
  static const canonical12U = ZoneProfile(bottomInches: 15.5, topInches: 39.5);

  double get heightInches => topInches - bottomInches;

  /// `y_ground` (§3.1): the ground plane's `ZoneCoord.y`, derived as the
  /// batter's knee height over her zone height. Everything below it is the
  /// dirt band and the §11.1 hinge trigger.
  double get groundY => -(bottomInches / heightInches);

  /// Frontal-plane render ratio (§11.4): px-per-x-unit ÷ px-per-y-unit. One
  /// x-unit is 8.5″ for everyone; one y-unit is this batter's zone height, so
  /// this is 0.354 at 12U and rises for a smaller athlete.
  double get axisScaleRatio => plateHalfWidthInches / heightInches;
}

/// The batter silhouette (§11.4) — a frontal-plane cue for where she stands,
/// so a coach reads a call or an actual against a body rather than against an
/// empty rectangle.
///
/// **Derived from [profile], never drawn at a fixed size.** Its two
/// load-bearing landmarks are the zone's own edges: her knee is `y = 0` and
/// her armpit is `y = 1`, by definition of what the zone *is* (§3.1). She
/// therefore tracks the zone rect for every batter by construction and cannot
/// drift from it — which is what makes shipping her honest. A silhouette drawn
/// at one fixed height would be truthful only for a batter of that height and
/// would visibly contradict the zone rect for a tall or short kid, which is
/// why §11.4 kept her off the entry canvas until this was settled.
///
/// Everything else is human proportion expressed as a fraction of stature.
/// Those fractions are the only tuned numbers here, and they are marked.
class BatterSilhouette {
  const BatterSilhouette({this.profile = ZoneProfile.canonical12U});

  final ZoneProfile profile;

  /// Where the armpit sits as a fraction of stature — the bridge between the
  /// zone (which knows inches above ground) and anatomy (which knows fractions
  /// of height). Taken from §3.1's canonical pairing of a 39.5″ zone top with a
  /// ~58″ athlete, so [statureInches] returns 58″ at 12U and scales from there.
  static const double armpitFractionOfStature = 39.5 / 58;

  /// The batter's full height, implied by her zone rather than configured
  /// separately — one number cannot then disagree with the other.
  double get statureInches => profile.topInches / armpitFractionOfStature;

  /// A height above the ground, in inches, expressed in `ZoneCoord.y`.
  double yAtInches(double inchesAboveGround) =>
      (inchesAboveGround - profile.bottomInches) / profile.heightInches;

  /// A fraction of stature, expressed in `ZoneCoord.y`.
  double yAtStatureFraction(double fraction) =>
      yAtInches(statureInches * fraction);

  // Vertical landmarks. The first three are definitional; the rest are
  // proportion. Standing figure, feet on the ground line.
  double get feetY => profile.groundY;
  double get kneeY => zoneMinY; // y = 0, the zone's bottom edge
  double get armpitY => zoneMaxY; // y = 1, the zone's top edge
  double get hipY => yAtStatureFraction(0.47);
  double get shoulderY => yAtStatureFraction(0.82);
  double get chinY => yAtStatureFraction(0.87);

  /// Top of the head — **above the canvas** at 12U (y = 1.771 against a +1.5
  /// top), so she is frame-cut at upper-face level. That is the top trim doing
  /// exactly what §11.4 designed it to do, not a shortfall: nothing above the
  /// letters carries scouting information, and a figure continuing past the
  /// frame reads as a figure rather than as a small complete person.
  double get headTopY => yAtStatureFraction(1);

  // Profile dimensions, in inches, as fractions of stature. The batter stands
  // side-on with the chest turned toward the plate, so what the lateral axis
  // shows is chest *depth*, not shoulder breadth — a batter in the box is a
  // much narrower shape than a person standing square to the camera.
  double get chestDepthInches => statureInches * 0.15;
  double get headDepthInches => statureInches * 0.13;
  double get thighWidthInches => statureInches * 0.09;
  double get shinWidthInches => statureInches * 0.07;
  double get armWidthInches => statureInches * 0.05;
  double get batLengthInches => statureInches * 0.55;

  /// Foot length as it reads laterally. The batter's feet point *at the plate*
  /// — square to the pitch, not along it — so the lateral axis shows close to
  /// their full length. Trimmed slightly from a true ~9″ shoe so the front toe
  /// stops at the chalk's inner edge rather than crossing out of the box.
  double get footLengthInches => statureInches * 0.15;

  /// How far the knee sits toward the plate of the ankle. A batting stance is
  /// a loaded athletic position: knees bent and driven forward over the feet,
  /// not straight legs.
  double get kneeForwardInches => statureInches * 0.07;

  /// Gap between the chalk's outer edge and the batter's *toes* — a few inches,
  /// which is where a batter actually sets up: close enough to cover the
  /// outside corner, off the line rather than on it.
  static const double stanceGapFromChalkInches = 3;

  /// Where the toes sit, in inches from plate centre. This is the anchor the
  /// whole figure is positioned by, because it is the thing a batter actually
  /// lines up: the feet against the chalk.
  double get toeInchesFromPlate =>
      BatterBoxSpec.outerChalkXUnits * plateHalfWidthInches +
      stanceGapFromChalkInches;

  /// How far the body centre sits from plate centre — **derived** by standing
  /// the feet at [toeInchesFromPlate] and working back along them. ≈ 29″ at
  /// 12U.
  double get stanceOffsetInches => toeInchesFromPlate + footLengthInches;

  /// Half the distance between the feet, along the **pitcher–catcher axis**.
  ///
  /// A batting stance separates the feet in depth, not across the plate: both
  /// feet sit the same distance from the box line, one simply stands nearer
  /// the catcher than the other. So there is no lateral spread at all — what
  /// separates them on screen is that nearer ground projects below `y_ground`
  /// and further ground above it, which the painter reads from the ground
  /// projector rather than approximating.
  double get stanceDepthHalfInches => statureInches * 0.22;

  /// Signed lateral position of the body centre in x-units, in the box that
  /// side actually bats from.
  ///
  /// `x` is absolute and catcher's-view (§3.1), so this is the one place the
  /// handedness convention is written down: facing the pitcher from behind the
  /// plate, first base is on the right, so **positive x is the first-base
  /// side**. A right-handed batter stands on the third-base side and therefore
  /// at *negative* x — which the broadcast reference confirms. Getting this
  /// backwards is the classic version of this bug, and it is silent.
  double centreXUnits({required bool rightHanded}) =>
      (rightHanded ? -1 : 1) * stanceOffsetInches / plateHalfWidthInches;

  /// Which lateral direction the plate lies in from the batter, as a sign on
  /// the x axis. The whole figure is built facing this way.
  double towardPlateSign({required bool rightHanded}) => rightHanded ? 1 : -1;

  /// Outermost extent in x-units — the back foot, which is what has to stay
  /// inside the frame.
  double outerXUnits({required bool rightHanded}) =>
      centreXUnits(rightHanded: rightHanded).abs() +
      (chestDepthInches / 2) / plateHalfWidthInches;
}

/// The virtual camera for the ground projection (§11.4): height [heightInches]
/// above the ground, [distanceInches] horizontally from the plate's 17″ far
/// edge, azimuth 0 (directly behind the plate, so the plate stays laterally
/// symmetric and registration against `x = ±1` holds).
class GroundCamera {
  const GroundCamera({
    required this.heightInches,
    required this.distanceInches,
  });

  /// `H` — camera height above the ground.
  final double heightInches;

  /// `d` — horizontal distance to the plate's 17″ far edge.
  final double distanceInches;

  /// §11.4's default: H = 4 ft, d = 20 ft. Renders the plate at 0.215.
  static const defaultCamera = GroundCamera(
    heightInches: 48,
    distanceInches: 240,
  );

  /// Plate on-screen depth ÷ width. `d − 17″` is the plate's *near* point,
  /// which is closer to the camera than the 17″ edge `d` measures to; a
  /// `d + 17″` here is the sign error to watch for (§11.4).
  double get plateDepthRatio =>
      heightInches / (distanceInches - plateDepthInches);

  /// How much wider than `x = ±1` the plate's near corners project. 1.05 = 5%.
  double get nearCornerSplay =>
      distanceInches / (distanceInches - plateHalfWidthInches);

  /// Accepted foreshortening band (§11.4).
  static const double minPlateDepthRatio = 0.15;
  static const double maxPlateDepthRatio = 0.25;

  /// Splay limit: the plate must still read as a plate, not a trapezoid.
  static const double maxNearCornerSplay = 1.05;

  /// The two constraints are **coupled** — satisfying one does not satisfy the
  /// other (§11.4). At H = 4 ft the ratio band binds first, so d = 15 ft is
  /// illegal (0.294) despite passing the splay rule. Anything choosing a
  /// camera, test fixtures included, checks both.
  List<String> get violations {
    final ratio = plateDepthRatio.toStringAsFixed(3);
    final splayPct = ((nearCornerSplay - 1) * 100).toStringAsFixed(1);
    final splayLimitPct = ((maxNearCornerSplay - 1) * 100).toStringAsFixed(0);
    const band = '[$minPlateDepthRatio, $maxPlateDepthRatio]';
    return [
      if (plateDepthRatio < minPlateDepthRatio ||
          plateDepthRatio > maxPlateDepthRatio)
        'plate depth ratio $ratio outside $band',
      if (nearCornerSplay > maxNearCornerSplay)
        'near-corner splay $splayPct% exceeds $splayLimitPct%',
    ];
  }

  bool get isValid => violations.isEmpty;
}

/// Canvas capture extents (§11.4). A release inside these commits; outside
/// cancels. These are layout calls — the only ones in the frontal geometry —
/// everything else is derived.
///
/// Lateral reaches ±4.0 to contain **where the batter stands**, not merely to
/// reach the chalk: a 12U stance puts her body centre around 26–30″ off plate
/// centre (x ≈ 3.1–3.5) spanning roughly x ∈ [2.4, 4.3], so the silhouette lays
/// over the outer third of the canvas with capture room on both sides of her,
/// and a pitch anywhere — including at her body — is recordable.
///
/// Widening is free in tap precision: the canvas is height-limited on a tablet,
/// so the zone's on-screen size is set by the vertical scale (one y-unit of
/// 2.85) and extra lateral range only adds pixels to the sides. What it does
/// spend is horizontal room, which competes with the call grid — which is why
/// this stops at ±4.0 rather than ±6.0, where the whole 36″ box would fit but
/// the outer ~20″ is empty chalk nobody stands in.
///
/// Vertically the top stops at **+1.5** — half a zone height above the zone,
/// ≈ 12″ over the letters, upper-face level at 12U. Above that carries no
/// scouting or development information: a foot over the head and two inches
/// over the head are the same observation, and §17.4 buckets both as
/// uncompetitive-high. Those pitches stay recordable, just unresolved, landing
/// on the top edge. Shoulder height (y ≈ 1.31) stays resolved, since an
/// elevated fastball is a real location rather than a miss.
///
/// Trimming the top is free: width-constrained (the side-by-side layout with
/// the call grid), the zone's on-screen size follows the lateral extent alone,
/// so this costs no tap precision and buys vertical room for the count HUD and
/// outcome row.
///
/// The bottom reaches a tappable margin below the plate's point.
const double zoneCanvasExtentMinX = -4;
const double zoneCanvasExtentMaxX = 4;
const double zoneCanvasExtentMinY = -1.05;
const double zoneCanvasExtentMaxY = 1.5;

/// The canvas's lateral coverage in inches — 68″ at ±4.0. Unlike the vertical
/// extent this is profile-independent, since one x-unit is 8.5″ for everyone
/// (§3.1).
const double zoneCanvasLateralExtentInches =
    (zoneCanvasExtentMaxX - zoneCanvasExtentMinX) * plateHalfWidthInches;

/// Batter's-box dimensions — a `RuleSet` concern (§11.4), never an
/// `if (softball)` branch. Offsets are measured to the chalk's *inner*
/// (plate-side) edge, matching the rulebook.
class BatterBoxSpec {
  const BatterBoxSpec({
    required this.widthInches,
    required this.foreInches,
    required this.aftInches,
  });

  /// Box width, running laterally away from the plate.
  final double widthInches;

  /// How far the box runs forward (toward the pitcher) of the plate's center.
  final double foreInches;

  /// How far it runs back (toward the catcher) of the plate's center.
  final double aftInches;

  static const fastpitch = BatterBoxSpec(
    widthInches: 36,
    foreInches: 48,
    aftInches: 36,
  );

  /// Gap from the plate's side edge to the chalk's inner edge.
  static const double offsetInches = 6;

  /// Chalk width, measured outward from that inner edge.
  static const double chalkWidthInches = 3;

  /// Lateral position of the chalk's inner edge, in x-units at plate depth:
  /// (8.5″ + 6″) / 8.5″ = 1.706.
  static double get innerChalkXUnits =>
      (plateHalfWidthInches + offsetInches) / plateHalfWidthInches;

  /// Lateral position of the chalk's outer edge — 2.059, which clips at the
  /// ±1.9 canvas edge. Intended, not a bug (§11.4).
  static double get outerChalkXUnits =>
      (plateHalfWidthInches + offsetInches + chalkWidthInches) /
      plateHalfWidthInches;
}

/// The frontal plane's projection: a plain scale-and-shift mapping for the
/// zone (height → y, equal steps stay equal), plus a pinhole perspective for
/// ground furniture (plate, dirt, boxes). The two coincide exactly at
/// the plate's depth, which is what puts the plate's front edge on `y_ground`
/// (§11.4) — an identity, independent of `H` and `d`.
class FrontalGeometry {
  const FrontalGeometry({
    this.profile = ZoneProfile.canonical12U,
    this.camera = GroundCamera.defaultCamera,
  });

  final ZoneProfile profile;
  final GroundCamera camera;

  double get groundY => profile.groundY;

  /// The camera's eye height, mapped through the height axis. Sits at y =
  /// +1.354 at the default camera — inside the canvas, above the zone rect —
  /// and is never drawn (§11.4).
  double get horizonY => groundY + camera.heightInches / profile.heightInches;

  /// Ground at camera-relative distance [u] → `ZoneCoord.y`. Anchored so that
  /// `u = d` maps to [groundY]; approaches [horizonY] as `u` grows.
  double groundYAt(double u) =>
      horizonY - (horizonY - groundY) * camera.distanceInches / u;

  /// Inverse of [groundYAt].
  ///
  /// **Deliberately not used to infer bounce depth (§11.4).** A tap above the
  /// ground line does correspond to a real distance out front, but the same
  /// pixel is also a legitimate airborne location — y = −0.40 is both ground
  /// 2.8 ft out and a pitch 5.9″ off the dirt at the plate — and airborne is
  /// overwhelmingly the common case. Taps above `y_ground` are airborne;
  /// bounce depth comes only from the hinge and the top-down plane (§3.3).
  /// This exists for tests and for drawing, never for reading a coordinate.
  double groundDistanceAtY(double y) =>
      (horizonY - groundY) * camera.distanceInches / (horizonY - y);

  /// Lateral world offset [lateralInches] at camera-relative distance [u],
  /// in x-units. Registration: 8.5″ at `u = d` maps to exactly 1.0.
  double xUnitsAt(double lateralInches, double u) =>
      (lateralInches / plateHalfWidthInches) * (camera.distanceInches / u);

  /// Camera-relative distance of the plate's center — the reference the
  /// batter's box is positioned fore and aft of.
  double get plateCenterU => camera.distanceInches - plateSideInches;

  /// The plate outline as (lateralInches, u) ground points, front edge first,
  /// going clockwise to the point. Drawn through [xUnitsAt]/[groundYAt].
  List<({double lateralInches, double u})> get plateOutline => [
    (lateralInches: -plateHalfWidthInches, u: camera.distanceInches),
    (lateralInches: plateHalfWidthInches, u: camera.distanceInches),
    (
      lateralInches: plateHalfWidthInches,
      u: camera.distanceInches - plateSideInches,
    ),
    (lateralInches: 0, u: camera.distanceInches - plateDepthInches),
    (
      lateralInches: -plateHalfWidthInches,
      u: camera.distanceInches - plateSideInches,
    ),
  ];

  /// Plate on-screen depth in y-units — the front edge sits on [groundY] and
  /// the point this far below it.
  double get plateOnScreenDepthYUnits =>
      camera.plateDepthRatio * (plateWidthInches / profile.heightInches);

  /// Canvas aspect ratio (width ÷ height) in world terms, which is what keeps
  /// the two axes' different scales honest (§3.1). Moves with the profile.
  double get aspectRatio =>
      (zoneCanvasExtentMaxX - zoneCanvasExtentMinX) *
      plateHalfWidthInches /
      ((zoneCanvasExtentMaxY - zoneCanvasExtentMinY) * profile.heightInches);

  /// Ground is drawn to its natural extent and bounded by a distance fade
  /// rather than a `y` cap (§11.4 v0.31): full tone below the ground line,
  /// fading to neutral by [groundFadeEndY], which stays below the zone rect so
  /// the grid never reads against busy dirt. A fidelity parameter — expect the
  /// endpoints to move during the fidelity comparison.
  static const double groundFadeEndY = -0.15;

  /// Fade weight at [y]: 1 at or below the ground line, 0 at the fade end.
  double groundFadeAt(double y) {
    if (y <= groundY) return 1;
    if (y >= groundFadeEndY) return 0;
    return 1 - (y - groundY) / (groundFadeEndY - groundY);
  }

  /// Where the inner chalk line becomes laterally on-canvas: closer ground
  /// splays wider, so the near end of each box runs off-frame. Solving
  /// `1.706·d/u ≤ maxX` gives `u ≥ 0.898 d` at the default camera (§11.4).
  double get innerChalkOnCanvasU =>
      BatterBoxSpec.innerChalkXUnits *
      camera.distanceInches /
      zoneCanvasExtentMaxX;

  /// Longest `u` still laterally on-canvas for a given world lateral offset —
  /// used to clip chalk at the frame edge rather than guessing.
  double maxOnCanvasU(double lateralInches) => math.max(
    camera.distanceInches *
        lateralInches /
        (zoneCanvasExtentMaxX * plateHalfWidthInches),
    0,
  );
}

/// The top-down plate/dirt plane (§3.3), entered by §11.1's dirt-band hinge and
/// left again on commit. Lateral × depth, where [FrontalGeometry] is lateral ×
/// height: **the two planes share the lateral axis and nothing else** (§3.3).
///
/// Nothing here converts a frontal-plane position into a depth, and nothing may
/// be added that does. The frontal plane's ground *is* invertible
/// ([FrontalGeometry.groundDistanceAtY]) and deliberately unused that way — the
/// same pixel is also a legitimate airborne location, which is the common case.
/// Depth exists only after the hinge, from a placement made in this plane.
///
/// Two constraints fix everything except where `depth = 0` sits:
///
/// - **Same px-per-x as the frontal plane** (§11.4). The plate is literally the
///   same width in both views, which is the strongest available cue that the
///   planes register — and it makes `x = ±1` the plate's 17″ edge here too,
///   with no second registration rule to keep in sync.
/// - **Isotropic** — true scale in both axes, no depth compression. Unlike the
///   frontal plane, whose axes differ by [ZoneProfile.axisScaleRatio] because
///   height normalizes per batter, ground geometry is the same for everyone.
class TopDownGeometry {
  const TopDownGeometry({this.frontal = const FrontalGeometry()});

  /// The frontal plane this one hinges from. Held rather than duplicated: the
  /// lateral axis and the drawing rect's shape both come from it, which is what
  /// keeps the two planes in register by construction rather than by matching
  /// literals in two places.
  final FrontalGeometry frontal;

  /// One foot of depth in x-units: 12″ / 8.5″ = 1.412. This *is* the isotropy
  /// constraint — the same px-per-inch in both axes — expressed in the units
  /// the lateral axis already uses.
  static const double xUnitsPerFoot = 12 / plateHalfWidthInches;

  /// Total depth the canvas covers, in inches.
  ///
  /// Derived, not chosen: sharing px-per-x with the frontal plane fixes
  /// px-per-inch, and the drawing rect's shape then fixes how many inches fit
  /// vertically. 61.2″ = 5.10 ft at 12U.
  ///
  /// It falls out to exactly the frontal plane's own vertical coverage in
  /// inches (`verticalExtent × zoneHeight`), which is asserted in the tests
  /// rather than assumed here. One consequence worth knowing: because the
  /// frontal rect's aspect follows the batter's zone height, so does this —
  /// a shorter batter's canvas is shallower, even though ground geometry
  /// itself does not vary with batter height (§3.3). The rect is the same
  /// rect; only what fills it changes.
  double get totalDepthInches =>
      zoneCanvasLateralExtentInches / frontal.aspectRatio;

  /// How far behind the plate's front edge the canvas reaches — toward the
  /// catcher, where `depth` is negative (§3.3).
  ///
  /// The one layout call in this class, and the only free parameter left once
  /// parity and isotropy are applied. 30″ holds the plate's full 17″ pentagon
  /// plus 13″ of catcher-side room, because a short hop landing just behind the
  /// front edge is a common bounce and not an edge case — the reason §3.3's
  /// depth sign convention exists at all. Fixed in *inches*, not as a fraction:
  /// the plate is 17″ for every batter, so the profile-dependent part of
  /// [totalDepthInches] is absorbed by the fore side instead.
  static const double aftExtentInches = 30;

  /// How far out in front of the plate the canvas reaches — 31.2″ (2.60 ft) at
  /// 12U, the remainder after [aftExtentInches].
  double get foreExtentInches => totalDepthInches - aftExtentInches;

  /// Depth in *feet* (`BounceCoord.depth`'s unit) at the canvas's top and
  /// bottom edges. Bounces beyond either land unresolved on the edge, the same
  /// treatment the frontal plane's +1.5 top gives an eye-level pitch (§11.4).
  double get maxDepthFeet => foreExtentInches / 12;
  double get minDepthFeet => -aftExtentInches / 12;

  /// Vertical position of `depth = 0` as a fraction of the rect, measured from
  /// the top. The seam the hinge lands on, and the plate's 17″ front edge.
  double get seamFraction => foreExtentInches / totalDepthInches;

  /// Depth (feet) at vertical fraction [fy], measured from the top of the rect.
  /// Depth grows *up*-screen toward the pitcher, matching the frontal plane's
  /// sense of "away from the catcher" (§11.4).
  double depthFeetAtFraction(double fy) =>
      (foreExtentInches - fy * totalDepthInches) / 12;

  /// Inverse of [depthFeetAtFraction].
  double fractionAtDepthFeet(double depthFeet) =>
      (foreExtentInches - depthFeet * 12) / totalDepthInches;

  /// Home plate from directly above: a true pentagon, no perspective (§11.4).
  /// The 17″ edge lies on `depth = 0`, its two 8.5″ sides run back to −8.5″,
  /// and the faces converge to the point at −17″. Same corner sequence as
  /// [FrontalGeometry.plateOutline], so the two views cannot drift apart.
  List<({double lateralInches, double depthInches})> get plateOutline => const [
    (lateralInches: -plateHalfWidthInches, depthInches: 0),
    (lateralInches: plateHalfWidthInches, depthInches: 0),
    (lateralInches: plateHalfWidthInches, depthInches: -plateSideInches),
    (lateralInches: 0, depthInches: -plateDepthInches),
    (lateralInches: -plateHalfWidthInches, depthInches: -plateSideInches),
  ];

  /// Depth of the plate's center — what the batter's box is positioned fore and
  /// aft of, mirroring [FrontalGeometry.plateCenterU].
  static const double plateCenterDepthInches = -plateSideInches;

  /// Depth gridline spacing. One foot, labeled — §11.4's 0–2 / 2–4 / 4 ft+
  /// bands are gone (v0.35): they assumed a range this plane's parity and
  /// isotropy constraints do not afford, and a continuous ruler suits a
  /// continuous float better than three buckets ever did. Nothing is bucketed
  /// in storage either way (§3.3).
  ///
  /// Labels read "1 ft" / "2 ft" on both sides of the seam, unsigned: the plate
  /// sits between them, so which side is toward the catcher is not something a
  /// label has to carry.
  static const double gridlineSpacingFeet = 1;
}
