/// Field profiles (spec §16.1–§16.2): the dimensions the field canvas
/// renders to scale from.
///
/// App-side config, deliberately not schema: profiles describe the park, not
/// what happened in it — no event carries one. M1 hardcodes the fastpitch 12U
/// preset (DIA-008); the team profile library and per-game overrides are the
/// M2 resolution order of §16.1.
library;

import 'dart:math' as math;

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/fence_spline.dart';

/// The five poles of the fence model (§16.1), in feet.
class FencePoles {
  const FencePoles({
    required this.lfLine,
    required this.lfGap,
    required this.cf,
    required this.rfGap,
    required this.rfLine,
  });

  final double lfLine; // θ = −45°
  final double lfGap; // θ = −22.5°
  final double cf; // θ = 0°
  final double rfGap; // θ = +22.5°
  final double rfLine; // θ = +45°
}

/// §16.1's profile, minus the library plumbing M1 doesn't have (`source`
/// exists once there is more than one place a profile can come from).
class FieldProfile {
  FieldProfile({
    required this.id,
    required this.label,
    required this.fence,
    required this.basePath,
    required this.pitchingDistance,
    this.backstop,
  }) : _fenceSpline = MonotoneCubicSpline(
         const [-math.pi / 4, -math.pi / 8, 0, math.pi / 8, math.pi / 4],
         [fence.lfLine, fence.lfGap, fence.cf, fence.rfGap, fence.rfLine],
       );

  final String id;
  final String label;
  final FencePoles fence;

  /// Feet between consecutive bases (60 / 65 / 70 / 90).
  final double basePath;

  /// Plate to pitching rubber, feet.
  final double pitchingDistance;

  /// Feet behind the plate, when known; affects the foul-territory render.
  final double? backstop;

  final MonotoneCubicSpline _fenceSpline;

  /// §16.2's `fenceDistanceAt(θ)`: fence distance in feet at bearing
  /// [theta] (radians, θ = 0 at CF, negative third-base side). Bearings
  /// beyond the foul poles clamp to the pole — the fence model ends there.
  double fenceDistanceAt(double theta) => _fenceSpline.at(theta);

  /// DIA-008's hardcoded preset (§16.1's builtin table, ⚠ draft values):
  /// fastpitch 12U — 190/200/210 fence, 60 ft bases, 40 ft pitching.
  static final fastpitch12U = FieldProfile(
    id: 'builtin-fastpitch-12u',
    label: 'Fastpitch 12U',
    fence: const FencePoles(
      lfLine: 190,
      lfGap: 200,
      cf: 210,
      rfGap: 200,
      rfLine: 190,
    ),
    basePath: 60,
    pitchingDistance: 40,
  );
}

/// Position abbreviations, the label vocabulary everywhere a position shows
/// on screen. Scoring numbers (1–9) stay in the event stream (§4.2), but
/// most people don't know the pitcher is 1 and the center fielder is 8 —
/// the UI speaks P/C/1B/…/RF.
const positionAbbreviations = <int, String>{
  1: 'P',
  2: 'C',
  3: '1B',
  4: '2B',
  5: '3B',
  6: 'SS',
  7: 'LF',
  8: 'CF',
  9: 'RF',
  10: 'OF4',
};

/// Profile-scaled standard defensive spots (§16.4's render defaults), keyed
/// by position number. Draft placements: bearings and depths are eyeballed
/// literals scaled by the profile's dimensions, good enough to render a
/// recognizable defense. Alignment drag (§16.4) is explicitly out of
/// DIA-008's scope, so nothing downstream may treat these as data.
Map<int, FieldCoord> standardFielderSpots(FieldProfile profile) {
  FieldCoord at(double thetaDegrees, double r) {
    final theta = thetaDegrees * math.pi / 180;
    return FieldCoord(x: r * math.sin(theta), y: r * math.cos(theta));
  }

  final base = profile.basePath;
  double outfield(double thetaDegrees) =>
      0.75 * profile.fenceDistanceAt(thetaDegrees * math.pi / 180);

  return {
    1: FieldCoord(x: 0, y: profile.pitchingDistance),
    2: FieldCoord(x: 0, y: -8),
    3: at(35, 1.05 * base),
    4: at(15, 1.45 * base),
    5: at(-35, 1.05 * base),
    6: at(-15, 1.45 * base),
    7: at(-28, outfield(-28)),
    8: at(0, outfield(0)),
    9: at(28, outfield(28)),
  };
}
