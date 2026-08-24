/// Field-canvas geometry (§16.3): the world↔screen transform for one
/// [FieldProfile] rendered into one canvas size.
///
/// World space is `FieldCoord` — absolute feet, home plate at the origin,
/// +y toward CF, bearing θ = atan2(x, y) (§3.2). Screen space is Flutter
/// pixels, plate near the bottom edge, CF up. One uniform scale on both
/// axes — feet are feet in every direction — centered laterally, so a tap
/// is a real coordinate and a distance label is honest arithmetic. Foul
/// territory is inside the transform like everywhere else: never clamp.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';

/// The two answers a base can give (§15.1 v0.43).
enum BaseCall { safe, out }

class FieldGeometry {
  FieldGeometry({required this.profile, required this.size}) {
    // World bounds. Laterally: the foul poles are the widest fair points
    // (|x| = r·sin 45°); add margin for foul ground past the lines. Up: the
    // deepest fence point plus the same margin. Down (behind the plate): the
    // backstop when the profile knows it, else a default deep enough to show
    // the catcher and the plate circle.
    final poleX =
        math.max(profile.fence.lfLine, profile.fence.rfLine) *
        math.sin(math.pi / 4);
    final behind = profile.backstop ?? _defaultBehindPlateFt;
    _worldHalfWidth = poleX + _marginFt;
    _worldMinY = -(behind + _marginFt);
    _worldMaxY = profile.fence.cf + _marginFt;

    final worldWidth = 2 * _worldHalfWidth;
    final worldHeight = _worldMaxY - _worldMinY;
    pxPerFoot = math.min(size.width / worldWidth, size.height / worldHeight);

    // Center the fitted world rect in the canvas on both axes.
    _originX = size.width / 2;
    _plateY = (size.height + (_worldMaxY + _worldMinY) * pxPerFoot) / 2;
  }

  /// Margin beyond the poles/fence, feet. A render allowance (tuned
  /// literal), not park data — real foul territory varies and §16.1's
  /// backstop field is the honest input when it arrives. Sized so the band
  /// past the fence is a comfortable tap target: §16.3's home-run
  /// classification is entered by tapping *out there*.
  static const double _marginFt = 25;

  /// Behind-plate extent when the profile has no backstop measurement, feet.
  /// Tuned literal: enough for the catcher spot and a landing tap behind the
  /// plate.
  static const double _defaultBehindPlateFt = 20;

  final FieldProfile profile;
  final Size size;

  /// Uniform scale, px per foot — public because painters size strokes and
  /// hit radii in feet and convert once.
  late final double pxPerFoot;

  late final double _worldHalfWidth;
  late final double _worldMinY;
  late final double _worldMaxY;
  late final double _originX;
  late final double _plateY;

  /// Screen position of home plate — the world origin.
  Offset get plate => Offset(_originX, _plateY);

  Offset toPx(FieldCoord c) =>
      Offset(_originX + c.x * pxPerFoot, _plateY - c.y * pxPerFoot);

  FieldCoord toField(Offset px) => FieldCoord(
    x: (px.dx - _originX) / pxPerFoot,
    y: (_plateY - px.dy) / pxPerFoot,
  );

  /// Distance from home plate in feet — the live label of §16.3.
  static double distanceFt(FieldCoord c) => math.sqrt(c.x * c.x + c.y * c.y);

  /// Bearing in radians, θ = 0 at CF, negative third-base side (§3.2).
  static double bearing(FieldCoord c) => math.atan2(c.x, c.y);

  /// Fair territory: |θ| ≤ 45° and in front of the plate's plane (§3.2).
  static bool isFair(FieldCoord c) =>
      c.y > 0 && bearing(c).abs() <= math.pi / 4 + 1e-9;

  /// Feet between [c] and the fence at c's bearing — negative beyond it.
  /// The §16.2 `fenceRelativeDepth` input and the `offWall` suggestion test.
  double fenceDepthFt(FieldCoord c) =>
      profile.fenceDistanceAt(bearing(c)) - distanceFt(c);

  /// Screen positions of the four bases. Bases sit on the basepath square:
  /// first at +45°, second straight out at basePath·√2, third at −45°,
  /// home at the origin.
  Offset baseCenter(int base) => toPx(baseCoord(base));

  /// Where a runner token sits for each base, in screen space — geometry,
  /// not painting, because the painter draws it and the surface hit-tests it
  /// and the two must agree. Base 0 offsets beside the plate (the batter's
  /// box side is cosmetic here — the canvas is a map, not the frontal
  /// plane); 4 sits on the plate, dimmed by the painter.
  Offset tokenCenter(int base) {
    return switch (base) {
      0 => plate + Offset(-7.5 * pxPerFoot, 0),
      4 => plate,
      _ => baseCenter(base),
    };
  }

  /// How far along the basepath a runner in motion renders (§15.1 v0.43):
  /// far enough to read as *running toward* the next base, near enough that
  /// nobody mistakes it for having arrived.
  static const double inMotionFraction = 1 / 3;

  /// Where a runner token sits. A runner the play has only *presumed* into
  /// motion — the walk-up on contact — renders a third of the way from
  /// where the play found her toward the base she's headed for; a runner
  /// the scorer has resolved stands on her base.
  Offset runnerTokenCenter({
    required int base,
    int? origin,
    bool inMotion = false,
  }) {
    if (!inMotion || origin == null || origin == base) return tokenCenter(base);
    return Offset.lerp(
      tokenCenter(origin),
      tokenCenter(base),
      inMotionFraction,
    )!;
  }

  /// How far apart the stacked SAFE/OUT pills sit, in **pixels** — this is
  /// a touch-target distance, not a field measurement, so it must not
  /// shrink with the canvas. They can sit this close because [pillAt]
  /// resolves by nearest rather than first-within-radius: the midline
  /// between them is the boundary, so there is no ambiguous overlap.
  static const double _stackHalfPx = 30;

  /// How far into foul ground the pair sits beside first and third, feet:
  /// off the bag and out of the infield, without wandering away from the
  /// base it belongs to.
  static const double _towardFoulFt = 20;

  /// Hit radius for the SAFE/OUT pills. The painter lights up whichever
  /// pill this finds and the gesture code resolves to the same one — what
  /// glows is what happens.
  static const double affordanceHitRadiusPx = 36;

  /// §15.1 v0.43's paired drop targets, appearing only as a dragged runner
  /// approaches a base (or a throw arrives there). The pair **stacks** —
  /// SAFE on top, OUT beneath — so two targets are never side by side under
  /// one thumb. Where the stack sits is per base: out in foul ground beside
  /// first and third, and straddling the bag at second and home — safe
  /// toward the outfield, out toward the mound at second; safe toward the
  /// mound, out behind the plate at home. The base itself also reads as
  /// safe.
  Offset outAffordanceCenter(int base) => _baseAffordance(base, outward: true);

  Offset safeAffordanceCenter(int base) =>
      _baseAffordance(base, outward: false);

  Offset _baseAffordance(int base, {required bool outward}) {
    final center = base == 4 ? plate : baseCenter(base);
    final anchor = switch (base) {
      1 => center + Offset(_towardFoulFt * pxPerFoot, 0),
      3 => center - Offset(_towardFoulFt * pxPerFoot, 0),
      _ => center, // second and home: the stack straddles the bag
    };
    // Screen y grows downward, so SAFE (not outward) is the negative half.
    return anchor + Offset(0, (outward ? 1 : -1) * _stackHalfPx);
  }

  /// Which of [base]'s pills [px] lands on, or null for neither. Nearest
  /// wins, so the midline between the two is the boundary.
  BaseCall? pillAt(int base, Offset px) {
    final toSafe = (px - safeAffordanceCenter(base)).distance;
    final toOut = (px - outAffordanceCenter(base)).distance;
    if (toSafe > affordanceHitRadiusPx && toOut > affordanceHitRadiusPx) {
      return null;
    }
    return toSafe <= toOut ? BaseCall.safe : BaseCall.out;
  }

  /// The base a point is engaged with, or null — drives when the SAFE/OUT
  /// pair shows and which base a release resolves against. Measured to the
  /// nearer of the bag and its two pills, so reaching for a pill never
  /// takes the runner out of range of the base it belongs to.
  int? nearestBaseWithin(Offset px, double radius) {
    int? nearest;
    var best = radius;
    for (final base in const [1, 2, 3, 4]) {
      final center = base == 4 ? plate : baseCenter(base);
      final d = [
        (px - center).distance,
        (px - safeAffordanceCenter(base)).distance,
        (px - outAffordanceCenter(base)).distance,
      ].reduce((a, b) => a < b ? a : b);
      if (d <= best) {
        best = d;
        nearest = base;
      }
    }
    return nearest;
  }

  FieldCoord baseCoord(int base) {
    final half = profile.basePath * math.sin(math.pi / 4);
    return switch (base) {
      1 => FieldCoord(x: half, y: half),
      2 => FieldCoord(x: 0, y: 2 * half),
      3 => FieldCoord(x: -half, y: half),
      _ => FieldCoord(x: 0, y: 0), // 0 and 4: the plate
    };
  }
}
