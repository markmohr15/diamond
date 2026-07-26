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

  static const baseball = BatterBoxSpec(
    widthInches: 48,
    foreInches: 36,
    aftInches: 36,
  );
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
/// ground furniture (plate, dirt, boxes, catcher). The two coincide exactly at
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
