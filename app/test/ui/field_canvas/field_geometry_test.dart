import 'dart:math' as math;
import 'dart:ui';

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/field_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final geometry = FieldGeometry(
    profile: FieldProfile.fastpitch12U,
    size: const Size(800, 900),
  );

  group('FieldGeometry (§16.3): world ↔ screen', () {
    test('round-trips coordinates', () {
      final original = FieldCoord(x: -87.5, y: 143.25);
      final back = geometry.toField(geometry.toPx(original));
      expect(back.x, closeTo(original.x, 1e-9));
      expect(back.y, closeTo(original.y, 1e-9));
    });

    test('one uniform scale: feet are feet in every direction', () {
      final right = geometry.toPx(FieldCoord(x: 10, y: 0));
      final up = geometry.toPx(FieldCoord(x: 0, y: 10));
      final plate = geometry.plate;
      expect((right - plate).distance, closeTo((up - plate).distance, 1e-9));
      expect((right - plate).distance, closeTo(10 * geometry.pxPerFoot, 1e-9));
    });

    test('screen orientation: CF is up, first base is right of home', () {
      final cf = geometry.toPx(FieldCoord(x: 0, y: 210));
      expect(cf.dy, lessThan(geometry.plate.dy));
      expect(geometry.baseCenter(1).dx, greaterThan(geometry.plate.dx));
    });

    test('the world rect fits the canvas — fence and margin on-screen', () {
      for (final theta in [-math.pi / 4, 0.0, math.pi / 4]) {
        final r = geometry.profile.fenceDistanceAt(theta);
        final px = geometry.toPx(
          FieldCoord(x: r * math.sin(theta), y: r * math.cos(theta)),
        );
        expect(px.dx, inInclusiveRange(0, 800), reason: 'θ=$theta');
        expect(px.dy, inInclusiveRange(0, 900), reason: 'θ=$theta');
      }
    });

    test('foul territory is transformed, never clamped (§3.2)', () {
      final foul = FieldCoord(x: -60, y: 20); // well past the third-base line
      final back = geometry.toField(geometry.toPx(foul));
      expect(back.x, closeTo(-60, 1e-9));
      expect(back.y, closeTo(20, 1e-9));
    });
  });

  group('the SAFE/OUT pair (§15.1 v0.43)', () {
    test('stacks vertically at every base — SAFE on top, OUT beneath, never '
        'side by side', () {
      for (final base in [1, 2, 3, 4]) {
        final safe = geometry.safeAffordanceCenter(base);
        final out = geometry.outAffordanceCenter(base);
        expect(safe.dx, closeTo(out.dx, 1e-9), reason: 'base $base');
        expect(safe.dy, lessThan(out.dy), reason: 'base $base');
        // Close, but never ambiguous: pillAt resolves by nearest, so the
        // midline between them is the boundary.
        expect((out.dy - safe.dy).abs(), greaterThanOrEqualTo(56));
        expect(
          geometry.pillAt(base, safe),
          BaseCall.safe,
          reason: 'base $base',
        );
        expect(geometry.pillAt(base, out), BaseCall.out, reason: 'base $base');
        final midline = Offset(safe.dx, (safe.dy + out.dy) / 2);
        expect(
          geometry.pillAt(base, midline + const Offset(0, -1)),
          BaseCall.safe,
          reason: 'above the midline is safe at base $base',
        );
        expect(
          geometry.pillAt(base, midline + const Offset(0, 1)),
          BaseCall.out,
          reason: 'below the midline is out at base $base',
        );
      }
    });

    test('first and third put the pair in foul ground, clear of the '
        'basepath', () {
      for (final base in [1, 3]) {
        for (final pill in [
          geometry.safeAffordanceCenter(base),
          geometry.outAffordanceCenter(base),
        ]) {
          expect(
            FieldGeometry.isFair(geometry.toField(pill)),
            isFalse,
            reason: 'base $base',
          );
        }
      }
      // On the correct side of the diamond, each.
      expect(
        geometry.safeAffordanceCenter(1).dx,
        greaterThan(geometry.baseCenter(1).dx),
      );
      expect(
        geometry.safeAffordanceCenter(3).dx,
        lessThan(geometry.baseCenter(3).dx),
      );
    });

    test('second and home straddle the bag: safe toward the outfield at '
        'second, out behind the plate at home', () {
      expect(
        geometry.safeAffordanceCenter(2).dx,
        closeTo(geometry.baseCenter(2).dx, 1e-9),
      );
      expect(
        geometry.toField(geometry.safeAffordanceCenter(2)).y,
        greaterThan(geometry.baseCoord(2).y),
      );
      expect(
        geometry.toField(geometry.outAffordanceCenter(4)).y,
        lessThan(0),
        reason: 'behind the plate',
      );
      expect(
        geometry.toField(geometry.safeAffordanceCenter(4)).y,
        greaterThan(0),
        reason: 'toward the mound',
      );
    });

    test('reaching a pill keeps its base engaged, so the pair cannot vanish '
        'under the thumb', () {
      for (final base in [1, 2, 3, 4]) {
        for (final pill in [
          geometry.safeAffordanceCenter(base),
          geometry.outAffordanceCenter(base),
        ]) {
          expect(
            geometry.nearestBaseWithin(pill, FieldPainter.approachRadiusPx),
            base,
          );
        }
      }
    });
  });

  group('derived quantities', () {
    test('distance and bearing (§3.2 conventions)', () {
      final c = FieldCoord(x: -45, y: 120);
      expect(FieldGeometry.distanceFt(c), closeTo(128.16, 0.01));
      expect(FieldGeometry.bearing(c), lessThan(0)); // third-base side
      expect(FieldGeometry.bearing(FieldCoord(x: 0, y: 99)), 0);
    });

    test('fair/foul from the bearing', () {
      expect(FieldGeometry.isFair(FieldCoord(x: 50, y: 51)), isTrue);
      expect(FieldGeometry.isFair(FieldCoord(x: 50, y: 49)), isFalse);
      expect(FieldGeometry.isFair(FieldCoord(x: 0, y: -5)), isFalse);
    });

    test('fenceDepthFt: positive short of the wall, zero on it, negative '
        'beyond (§16.2)', () {
      expect(
        geometry.fenceDepthFt(FieldCoord(x: 0, y: 200)),
        closeTo(10, 1e-9),
      );
      expect(geometry.fenceDepthFt(FieldCoord(x: 0, y: 210)), closeTo(0, 1e-9));
      expect(
        geometry.fenceDepthFt(FieldCoord(x: 0, y: 220)),
        closeTo(-10, 1e-9),
      );
    });

    test(
      'bases sit on the basepath square (§16.3: rendered from basePath)',
      () {
        final first = geometry.baseCoord(1);
        final second = geometry.baseCoord(2);
        final third = geometry.baseCoord(3);
        expect(FieldGeometry.distanceFt(first), closeTo(60, 1e-9));
        expect(FieldGeometry.distanceFt(third), closeTo(60, 1e-9));
        expect(
          FieldGeometry.distanceFt(
            FieldCoord(x: second.x - first.x, y: second.y - first.y),
          ),
          closeTo(60, 1e-9),
        );
        expect(FieldGeometry.bearing(first), closeTo(math.pi / 4, 1e-9));
      },
    );
  });
}
