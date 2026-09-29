/// Naming the part of the field a ball came down in (§3.2, §17's spray
/// charts), for the plays whose narration has no fielder to point at.
library;

import 'dart:math' as math;

import 'package:diamond/src/events/generated/events.dart';

/// The five sectors a batted ball is described by, foul line to foul line.
///
/// Five because that is how a spray chart is read aloud — *to left*, *to
/// left-center* — and because the gaps are the interesting places: a ball
/// to left-center is a different event from one to left, and collapsing
/// them loses the distinction a coach is watching for.
enum SpraySector {
  left('left'),
  leftCenter('left-center'),
  center('center'),
  rightCenter('right-center'),
  right('right');

  const SpraySector(this.label);

  /// How it reads in a sentence: "doubled to left-center".
  final String label;
}

/// Where [landing] came down, by bearing.
///
/// §3.2's convention throughout: home plate is the origin, θ = 0 points at
/// center field, and negative θ is the third-base side — so the sign of
/// `x` is the side of the field. Foul lines sit at ±45°, and the 90° between
/// them divides into five equal 18° bands.
///
/// **Only for a ball nobody touched.** Where a touch exists the narration
/// names the fielder instead, which is both more precise and what a scorer
/// says; an untouched ball is one that reached the outfield or left the
/// yard, since in the infield somebody picks it up eventually (Mark,
/// 2026-09-29). A ball behind the plate is not a sector question either —
/// foul territory has no name here.
SpraySector sectorFor(FieldCoord landing) {
  // atan2(x, y), not the usual (y, x): θ is measured off the center-field
  // axis rather than off the first-base line, which is what makes θ = 0 the
  // middle of the field and the sign of x the side of it.
  final degrees = math.atan2(landing.x, landing.y) * 180 / math.pi;
  // Clamped rather than asserted: a ball hooking foul still came down
  // somewhere, and the nearest sector is the honest name for it.
  final clamped = degrees.clamp(-45.0, 45.0);
  if (clamped < -27) return SpraySector.left;
  if (clamped < -9) return SpraySector.leftCenter;
  if (clamped <= 9) return SpraySector.center;
  if (clamped <= 27) return SpraySector.rightCenter;
  return SpraySector.right;
}
