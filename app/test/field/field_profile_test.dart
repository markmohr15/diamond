import 'dart:math' as math;

import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final profile = FieldProfile.fastpitch12U;

  group('FieldProfile.fastpitch12U (§16.1 builtin, draft values)', () {
    test('carries the preset dimensions', () {
      expect(profile.sport, Sport.softball);
      expect(profile.fence.lfLine, 190);
      expect(profile.fence.lfGap, 200);
      expect(profile.fence.cf, 210);
      expect(profile.fence.rfGap, 200);
      expect(profile.fence.rfLine, 190);
      expect(profile.basePath, 60);
      expect(profile.pitchingDistance, 40);
    });

    test('fenceDistanceAt hits the five poles exactly (§16.2)', () {
      expect(profile.fenceDistanceAt(-math.pi / 4), closeTo(190, 1e-9));
      expect(profile.fenceDistanceAt(-math.pi / 8), closeTo(200, 1e-9));
      expect(profile.fenceDistanceAt(0), closeTo(210, 1e-9));
      expect(profile.fenceDistanceAt(math.pi / 8), closeTo(200, 1e-9));
      expect(profile.fenceDistanceAt(math.pi / 4), closeTo(190, 1e-9));
    });
  });

  group('standardFielderSpots (§16.4 render defaults)', () {
    final spots = standardFielderSpots(profile);

    test('all nine positions, pitcher on the rubber, catcher behind plate', () {
      expect(spots.keys, unorderedEquals([1, 2, 3, 4, 5, 6, 7, 8, 9]));
      expect(spots[1]!.x, 0);
      expect(spots[1]!.y, profile.pitchingDistance);
      expect(spots[2]!.y, lessThan(0));
    });

    test('everyone but the catcher stands in fair territory, inside the '
        'fence', () {
      for (final entry in spots.entries) {
        if (entry.key == 2) continue;
        final spot = entry.value;
        expect(
          FieldGeometry.isFair(spot),
          isTrue,
          reason: 'position ${entry.key}',
        );
        final bearing = FieldGeometry.bearing(spot);
        expect(
          FieldGeometry.distanceFt(spot),
          lessThan(profile.fenceDistanceAt(bearing)),
          reason: 'position ${entry.key}',
        );
      }
    });

    test('infield sits near the basepaths, outfield well beyond them', () {
      for (final position in const [3, 4, 5, 6]) {
        expect(
          FieldGeometry.distanceFt(spots[position]!),
          inInclusiveRange(profile.basePath, 2 * profile.basePath),
          reason: 'position $position',
        );
      }
      for (final position in const [7, 8, 9]) {
        expect(
          FieldGeometry.distanceFt(spots[position]!),
          greaterThan(2 * profile.basePath),
          reason: 'position $position',
        );
      }
    });
  });
}
