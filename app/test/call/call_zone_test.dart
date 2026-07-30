import 'package:diamond/src/call/call_zone.dart';
import 'package:diamond/src/call/canonical_cells.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter_test/flutter_test.dart';

/// The nine in-zone cells as nine separate zones — the finest in-zone layout.
List<CallZone> _nineInZone() => [
  for (final cell in canonicalCells.where((c) => c.isInZone))
    CallZone(id: cell.id, label: cell.id, cells: [cell]),
];

/// The coarse layout an older team would outgrow: 9 in-zone cells separate,
/// and the whole 16-cell ring grouped into four chase zones by edge, with the
/// corners folded into the vertical ones.
CallZoneLayout _coarseLayout() {
  final ring = canonicalCells.where((c) => !c.isInZone).toList();
  return CallZoneLayout(
    id: 'coarse',
    zones: [
      ..._nineInZone(),
      CallZone(
        id: 'chase-low',
        label: 'Bury',
        cells: ring.where((c) => c.row == 0).toList(),
      ),
      CallZone(
        id: 'chase-high',
        label: 'Chase High',
        cells: ring.where((c) => c.row == 4).toList(),
      ),
      CallZone(
        id: 'chase-left',
        label: 'Off Left',
        cells: ring
            .where((c) => c.column == 0 && c.row != 0 && c.row != 4)
            .toList(),
      ),
      CallZone(
        id: 'chase-right',
        label: 'Off Right',
        cells: ring
            .where((c) => c.column == 4 && c.row != 0 && c.row != 4)
            .toList(),
      ),
    ],
  );
}

/// Every cell its own zone — the finest layout possible.
CallZoneLayout _fineLayout() => CallZoneLayout(
  id: 'fine',
  zones: [
    for (final cell in canonicalCells)
      CallZone(id: cell.id, label: cell.id, cells: [cell]),
  ],
);

void main() {
  group('layout validation', () {
    test('accepts a coarse and a fine layout of the same 25 cells', () {
      expect(_coarseLayout().zones, hasLength(13));
      expect(_fineLayout().zones, hasLength(25));
    });

    test('rejects overlap — two zones claiming one cell', () {
      expect(
        () => CallZoneLayout(
          id: 'overlapping',
          zones: [
            ..._fineLayout().zones,
            const CallZone(
              id: 'greedy',
              label: 'Greedy',
              cells: [CanonicalCell(2, 2)],
            ),
          ],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('may not overlap'),
          ),
        ),
      );
    });

    test('rejects a gap — a cell no zone claims', () {
      expect(
        () => CallZoneLayout(id: 'gappy', zones: _nineInZone()),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('uncovered'),
          ),
        ),
      );
    });

    test('rejects an empty zone', () {
      expect(
        () => CallZoneLayout(
          id: 'empty-zone',
          zones: [
            ..._fineLayout().zones,
            const CallZone(id: 'nothing', label: 'Nothing', cells: []),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('containment', () {
    test('every point resolves to exactly one zone, in both layouts', () {
      for (final layout in [_coarseLayout(), _fineLayout()]) {
        for (var x = -6.0; x <= 6.0; x += 0.25) {
          for (var y = -3.0; y <= 3.0; y += 0.25) {
            final coord = ZoneCoord(x: x, y: y);
            final owners = layout.zones
                .where((zone) => zone.contains(coord))
                .toList();
            expect(
              owners,
              hasLength(1),
              reason: '${layout.id} gave ${owners.length} zones for $coord',
            );
            expect(layout.zoneFor(coord), owners.single);
          }
        }
      }
    });
  });

  group('derived centroid', () {
    test('a single-cell zone targets that cell', () {
      const cell = CanonicalCell(1, 1);
      const zone = CallZone(id: 'z', label: 'z', cells: [cell]);
      expect(zone.centroid.x, closeTo(cell.centroid.x, 1e-12));
      expect(zone.centroid.y, closeTo(cell.centroid.y, 1e-12));
    });

    test('a grouped unbounded zone targets the mean of its cells, not the '
        'centroid of an infinite rect', () {
      final chaseHigh = _coarseLayout().byId('chase-high')!;

      expect(chaseHigh.bounds.isUnbounded, isTrue);
      expect(chaseHigh.centroid.x.isFinite, isTrue);
      expect(chaseHigh.centroid.y.isFinite, isTrue);

      // Five cells across the top row: columns 0..4, symmetric about x = 0.
      expect(chaseHigh.cells, hasLength(5));
      expect(chaseHigh.centroid.x, closeTo(0, 1e-12));
      expect(chaseHigh.centroid.y, closeTo(1 + 1 / 6, 1e-12));
    });

    test('a grouped zone targets a point inside itself', () {
      for (final layout in [_coarseLayout(), _fineLayout()]) {
        for (final zone in layout.zones) {
          expect(
            zone.contains(zone.centroid),
            isTrue,
            reason: '${zone.id} targets a point outside itself',
          );
        }
      }
    });
  });

  group('absolute resolution', () {
    test('a grouped zone mirrors as a whole, matching the mean of its '
        'mirrored cells', () {
      final offAway = CallZone(
        id: 'off-away',
        label: 'Off Away',
        cells: canonicalCells.where((c) => c.column == 4).toList(),
      );

      for (final side in BatterSide.values) {
        final meanOfMirrored =
            offAway.cells
                .map((cell) => cell.absoluteCentroid(side).x)
                .reduce((a, b) => a + b) /
            offAway.cells.length;
        expect(
          offAway.absoluteCentroid(side).x,
          closeTo(meanOfMirrored, 1e-12),
        );
      }
    });

    test('height is untouched by handedness', () {
      final bury = CallZone(
        id: 'bury',
        label: 'Bury',
        cells: canonicalCells.where((c) => c.row == 0).toList(),
      );
      expect(
        bury.absoluteCentroid(BatterSide.L).y,
        bury.absoluteCentroid(BatterSide.R).y,
      );
      expect(bury.absoluteCentroid(BatterSide.R).y, bury.centroid.y);
    });
  });

  group('chase is derived, never stored', () {
    test('in-zone zones are not chases; ring zones are', () {
      final layout = _fineLayout();
      for (final zone in layout.zones) {
        expect(
          zone.isChase,
          !zone.cells.single.isInZone,
          reason: '${zone.id} chase classification',
        );
      }
    });

    test('a grouped edge zone is a chase', () {
      expect(_coarseLayout().byId('chase-low')!.isChase, isTrue);
      expect(_coarseLayout().byId('chase-right')!.isChase, isTrue);
    });
  });
}
