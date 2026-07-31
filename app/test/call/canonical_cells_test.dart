import 'package:diamond/src/call/canonical_cells.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the canonical partition', () {
    test('is 25 cells, 9 of them in the zone', () {
      expect(canonicalCells, hasLength(25));
      expect(canonicalCells.where((c) => c.isInZone), hasLength(9));
    });

    test('covers every point, however far off the plate', () {
      // Deliberately absurd: a pitch behind the batter, one over the backstop.
      // §17.4 must still resolve them, so the partition cannot have an edge.
      final far = [
        ZoneCoord(x: -40, y: -12),
        ZoneCoord(x: 40, y: 12),
        ZoneCoord(x: 0, y: -0.646), // the ground plane at 12U
        ZoneCoord(x: 3.5, y: 0.5), // out where the batter stands
      ];
      for (final coord in far) {
        expect(
          () => cellContaining(coord),
          returnsNormally,
          reason: '$coord resolved to no cell',
        );
      }
    });

    test('assigns each point to exactly one cell', () {
      // Walk a grid that straddles every boundary, including the zone edges
      // where two cells meet.
      for (var x = -3.0; x <= 3.0; x += 0.125) {
        for (var y = -2.0; y <= 2.0; y += 0.125) {
          final coord = ZoneCoord(x: x, y: y);
          final owners = canonicalCells
              .where((cell) => cell.bounds.contains(coord))
              .toList();
          expect(owners, hasLength(1), reason: '$coord had ${owners.length}');
        }
      }
    });

    test('the zone corners land in the zone, not the ring', () {
      // x = ±1 and y = 0/1 are the zone's own edges (§3.1). Half-open bounds
      // put the lower edges inside and the upper edges in the ring, which is
      // arbitrary but must be consistent — the alternative is a point owned
      // twice.
      expect(cellContaining(ZoneCoord(x: -1, y: 0)).isInZone, isTrue);
      expect(cellContaining(ZoneCoord(x: 0.99, y: 0.99)).isInZone, isTrue);
      expect(cellContaining(ZoneCoord(x: 1, y: 0.5)).isInZone, isFalse);
      expect(cellContaining(ZoneCoord(x: 0, y: 1)).isInZone, isFalse);
    });
  });

  group('centroids', () {
    test('in-zone cells target their true center', () {
      // Middle-middle is dead center of the plate, mid-zone.
      expect(const CanonicalCell(2, 2).centroid.x, closeTo(0, 1e-12));
      expect(const CanonicalCell(2, 2).centroid.y, closeTo(0.5, 1e-12));
      // The low-left in-zone cell centers a third of the way in and up.
      expect(const CanonicalCell(1, 1).centroid.x, closeTo(-2 / 3, 1e-12));
      expect(const CanonicalCell(1, 1).centroid.y, closeTo(1 / 6, 1e-12));
    });

    test('ring cells target half a cell beyond the edge, not the middle of '
        'an infinite region', () {
      expect(const CanonicalCell(4, 2).centroid.x, closeTo(1 + 1 / 3, 1e-12));
      expect(const CanonicalCell(0, 2).centroid.x, closeTo(-1 - 1 / 3, 1e-12));
      expect(const CanonicalCell(2, 4).centroid.y, closeTo(1 + 1 / 6, 1e-12));
      expect(const CanonicalCell(2, 0).centroid.y, closeTo(-1 / 6, 1e-12));
    });

    test('every centroid is finite, including the four ring corners', () {
      for (final cell in canonicalCells) {
        expect(cell.centroid.x.isFinite, isTrue, reason: '${cell.id} x');
        expect(cell.centroid.y.isFinite, isTrue, reason: '${cell.id} y');
      }
    });

    test('a centroid lands inside its own cell', () {
      for (final cell in canonicalCells) {
        expect(
          cellContaining(cell.centroid),
          cell,
          reason: '${cell.id} targets a point outside itself',
        );
      }
    });

    test('the spec figures hold at the 12U canonical profile', () {
      // §10.1 quotes these rounded; recomputed here from §3.1's inputs rather
      // than copied from the prose.
      const plateHalfWidthInches = 8.5;
      const zoneHeightInches = 39.5 - 15.5;
      const zoneBottomInches = 15.5;

      final lateralOffsetInches =
          const CanonicalCell(4, 2).centroid.x * plateHalfWidthInches -
          plateHalfWidthInches;
      expect(lateralOffsetInches, closeTo(2.83, 0.01));

      final offHighInches =
          zoneBottomInches +
          const CanonicalCell(2, 4).centroid.y * zoneHeightInches;
      expect(offHighInches, closeTo(43.5, 0.01));

      final offLowInches =
          zoneBottomInches +
          const CanonicalCell(2, 0).centroid.y * zoneHeightInches;
      expect(offLowInches, closeTo(11.5, 0.01));
    });
  });

  group('relative to absolute', () {
    // Positive x is the first-base side and a right-handed batter stands on
    // the third-base side (BatterSilhouette.centreXUnits), so "inside" is
    // negative x to a righty and positive to a lefty.
    test('inside is negative x for a righty and positive for a lefty', () {
      const inside = CanonicalCell(0, 2);
      expect(inside.absoluteCentroid(BatterSide.R).x, lessThan(0));
      expect(inside.absoluteCentroid(BatterSide.L).x, greaterThan(0));
    });

    test('away mirrors the other way', () {
      const away = CanonicalCell(4, 2);
      expect(away.absoluteCentroid(BatterSide.R).x, greaterThan(0));
      expect(away.absoluteCentroid(BatterSide.L).x, lessThan(0));
    });

    test('height never mirrors — high is high for everyone', () {
      for (final cell in canonicalCells) {
        expect(
          cell.absoluteCentroid(BatterSide.L).y,
          cell.absoluteCentroid(BatterSide.R).y,
          reason: '${cell.id} y moved with handedness',
        );
      }
    });

    test("the middle column sits on the plate's center line for both", () {
      const middle = CanonicalCell(2, 2);
      expect(middle.absoluteCentroid(BatterSide.R).x, closeTo(0, 1e-12));
      expect(middle.absoluteCentroid(BatterSide.L).x, closeTo(0, 1e-12));
    });

    test('a righty resolves to the relative frame unchanged', () {
      for (final cell in canonicalCells) {
        expect(cell.absoluteCentroid(BatterSide.R).x, cell.centroid.x);
      }
    });

    test('the two handednesses are reflections of each other', () {
      for (final cell in canonicalCells) {
        expect(
          cell.absoluteCentroid(BatterSide.L).x,
          closeTo(-cell.absoluteCentroid(BatterSide.R).x, 1e-12),
          reason: cell.id,
        );
      }
    });
  });

  group('bounds', () {
    test('only ring cells are unbounded', () {
      for (final cell in canonicalCells) {
        expect(
          cell.bounds.isUnbounded,
          !cell.isInZone,
          reason: '${cell.id} bounds',
        );
      }
    });

    test('in-zone cells are one third of the zone on each axis', () {
      final b = const CanonicalCell(2, 2).bounds;
      expect(b.maxX - b.minX, closeTo(CanonicalCell.columnWidth, 1e-12));
      expect(b.maxY - b.minY, closeTo(CanonicalCell.rowHeight, 1e-12));
    });
  });
}
