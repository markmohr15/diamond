import 'dart:math' as math;

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/spray_sector.dart';
import 'package:flutter_test/flutter_test.dart';

/// A landing 200 ft out at [degrees] off center field (§3.2: θ = 0 at CF,
/// negative toward third).
FieldCoord at(double degrees) {
  final theta = degrees * math.pi / 180;
  return FieldCoord(x: 200 * math.sin(theta), y: 200 * math.cos(theta));
}

void main() {
  test('the five bands, foul line to foul line', () {
    expect(sectorFor(at(-44)), SpraySector.left);
    expect(sectorFor(at(-30)), SpraySector.left);
    expect(sectorFor(at(-20)), SpraySector.leftCenter);
    expect(sectorFor(at(0)), SpraySector.center);
    expect(sectorFor(at(20)), SpraySector.rightCenter);
    expect(sectorFor(at(30)), SpraySector.right);
    expect(sectorFor(at(44)), SpraySector.right);
  });

  test('the sign of x is the side of the field', () {
    // The half the scorer is looking at, stated as a property rather than
    // as points: negative x is the third-base side, always.
    for (var d = 1.0; d < 45; d += 3) {
      expect(sectorFor(at(-d)).index, lessThan(SpraySector.center.index + 1));
      expect(sectorFor(at(d)).index, greaterThan(SpraySector.center.index - 1));
    }
  });

  test('the bands meet without a gap and without overlapping', () {
    // Walking the field in one-degree steps must produce the five sectors
    // in order and never go backwards — the boundaries are where they are
    // on purpose, and an off-by-one in a comparison shows up here.
    final seen = <SpraySector>[];
    for (var d = -45.0; d <= 45; d += 1) {
      final s = sectorFor(at(d));
      if (seen.isEmpty || seen.last != s) seen.add(s);
    }
    expect(seen, SpraySector.values);
  });

  test('a ball hooking foul takes the nearest sector rather than throwing', () {
    // It still came down somewhere, and the narration has to name it.
    expect(sectorFor(at(-60)), SpraySector.left);
    expect(sectorFor(at(60)), SpraySector.right);
  });

  test('a ball straight up the middle is center, however deep', () {
    expect(sectorFor(FieldCoord(x: 0, y: 30)), SpraySector.center);
    expect(sectorFor(FieldCoord(x: 0, y: 300)), SpraySector.center);
  });
}
