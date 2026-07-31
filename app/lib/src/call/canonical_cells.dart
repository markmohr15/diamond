import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter/foundation.dart';

/// A rectangle in `ZoneCoord` space, with infinite edges permitted.
///
/// Ring cells (§10.1) run outward without limit, so an ordinary finite rect
/// cannot express them: the canonical partition must cover every point, however
/// far off the plate, or containment classification (§17.4) would leave pitches
/// unresolvable.
@immutable
class ZoneRect {
  const ZoneRect({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  /// §10.1's *nominal* cell: one in-zone cell's dimensions, centered on
  /// [center].
  ///
  /// A ring cell's extent is unbounded — the partition may not have a hole, so
  /// containment (§17.4) resolves points however far off the plate — which
  /// leaves it with no geometric center and no rect anything could draw. §10.1
  /// supplies both by treating it as a cell of in-zone dimensions sitting
  /// immediately beyond the edge, and §11.4 makes that rect the swatch a
  /// callable zone paints. Equal dimensions throughout, so for anything already
  /// in the zone the nominal rect *is* the true one.
  factory ZoneRect.nominalCellAround(ZoneCoord center) => ZoneRect(
    minX: center.x - CanonicalCell.columnWidth / 2,
    maxX: center.x + CanonicalCell.columnWidth / 2,
    minY: center.y - CanonicalCell.rowHeight / 2,
    maxY: center.y + CanonicalCell.rowHeight / 2,
  );

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  /// Half-open on the upper edges, so adjacent cells share a boundary without
  /// both claiming it — the property that makes the partition a partition.
  /// The outermost cells are unbounded, so nothing falls off the top or right.
  bool contains(ZoneCoord coord) =>
      coord.x >= minX &&
      (coord.x < maxX || maxX == double.infinity) &&
      coord.y >= minY &&
      (coord.y < maxY || maxY == double.infinity);

  bool get isUnbounded =>
      minX == double.negativeInfinity ||
      maxX == double.infinity ||
      minY == double.negativeInfinity ||
      maxY == double.infinity;

  @override
  bool operator ==(Object other) =>
      other is ZoneRect &&
      other.minX == minX &&
      other.maxX == maxX &&
      other.minY == minY &&
      other.maxY == maxY;

  @override
  int get hashCode => Object.hash(minX, maxX, minY, maxY);

  @override
  String toString() => 'ZoneRect($minX..$maxX, $minY..$maxY)';
}

/// One of §10.1's 25 canonical cells: the fixed reference frame every team
/// layout is a grouping of.
///
/// Indices are **batter-relative** (§10.1): column 0 is furthest inside, column
/// 4 furthest away, whoever is batting. That is the frame the wristband is read
/// in — a code has to mean one thing to the pitcher, and *inside* is that
/// thing. Absolute coordinates (§3.1, catcher's view) come from
/// [absoluteCentroid], which mirrors for a left-handed batter; nothing here
/// stores an absolute x.
@immutable
class CanonicalCell {
  const CanonicalCell(this.column, this.row)
    : assert(column >= 0 && column <= 4, 'column is 0..4'),
      assert(row >= 0 && row <= 4, 'row is 0..4');

  /// 0..4, inside to away from the batter's point of view. 1..3 are in the
  /// zone.
  final int column;

  /// 0..4, bottom to top. 1..3 are in the zone.
  final int row;

  /// Stable identity for storage and for keying card entries.
  String get id => 'c${column}r$row';

  bool get isInZone => column >= 1 && column <= 3 && row >= 1 && row <= 3;

  /// The lateral boundaries: the plate spans `x ∈ [-1, 1]` (§3.1) split in
  /// thirds, with one unbounded stop beyond each edge.
  static const List<double> _columnEdges = [
    double.negativeInfinity,
    -1,
    -1 / 3,
    1 / 3,
    1,
    double.infinity,
  ];

  /// The vertical boundaries: the zone spans `y ∈ [0, 1]` — this batter's knee
  /// to armpit — split in thirds, with one unbounded stop beyond each edge.
  static const List<double> _rowEdges = [
    double.negativeInfinity,
    0,
    1 / 3,
    2 / 3,
    1,
    double.infinity,
  ];

  /// One in-zone column, in `ZoneCoord` x units.
  static const double columnWidth = 2 / 3;

  /// One in-zone row, in `ZoneCoord` y units.
  static const double rowHeight = 1 / 3;

  ZoneRect get bounds => ZoneRect(
    minX: _columnEdges[column],
    maxX: _columnEdges[column + 1],
    minY: _rowEdges[row],
    maxY: _rowEdges[row + 1],
  );

  /// The cell's target point (§10.1).
  ///
  /// In-zone cells use their true center. Ring cells are unbounded and so have
  /// no geometric center; their target is the center of a *nominal* cell of
  /// in-zone dimensions sitting immediately beyond the edge — half a cell out,
  /// which at 12U is ≈2.8″ past the plate edge laterally and ≈4″ past the knee
  /// or armpit vertically.
  ZoneCoord get centroid => ZoneCoord(x: _centerX, y: _centerY);

  /// The same target in **absolute** `ZoneCoord` (§3.1, catcher's view), for
  /// the batter in the box.
  ///
  /// Positive x is the first-base side and a right-handed batter stands on the
  /// third-base side at negative x — the convention is written down once, in
  /// `BatterSilhouette.centreXUnits`. So "inside" is negative x to a righty and
  /// positive x to a lefty, and only the lefty mirrors. `y` never mirrors: high
  /// is high for everyone.
  ///
  /// This is the only crossing from the relative frame to the absolute one, and
  /// it happens when the pitch is written (DIA-007), not when the call is made
  /// — the call screen has no batter.
  ///
  /// Used only by the test suite: production crosses frames a zone at a time,
  /// through `CallZone.absoluteCentroid` and [relativeToBatter]. Kept because a
  /// cell is what §10.1 defines the mirror on, and the tests pin it there.
  ZoneCoord absoluteCentroid(BatterSide side) =>
      ZoneCoord(x: side == BatterSide.L ? -_centerX : _centerX, y: _centerY);

  double get _centerX => switch (column) {
    0 => -1 - columnWidth / 2,
    4 => 1 + columnWidth / 2,
    _ => (_columnEdges[column] + _columnEdges[column + 1]) / 2,
  };

  double get _centerY => switch (row) {
    0 => -rowHeight / 2,
    4 => 1 + rowHeight / 2,
    _ => (_rowEdges[row] + _rowEdges[row + 1]) / 2,
  };

  @override
  bool operator ==(Object other) =>
      other is CanonicalCell && other.column == column && other.row == row;

  @override
  int get hashCode => Object.hash(column, row);

  @override
  String toString() => id;
}

/// All 25 canonical cells, in a stable order (row 0 first, then by column).
const List<CanonicalCell> canonicalCells = [
  CanonicalCell(0, 0),
  CanonicalCell(1, 0),
  CanonicalCell(2, 0),
  CanonicalCell(3, 0),
  CanonicalCell(4, 0),
  CanonicalCell(0, 1),
  CanonicalCell(1, 1),
  CanonicalCell(2, 1),
  CanonicalCell(3, 1),
  CanonicalCell(4, 1),
  CanonicalCell(0, 2),
  CanonicalCell(1, 2),
  CanonicalCell(2, 2),
  CanonicalCell(3, 2),
  CanonicalCell(4, 2),
  CanonicalCell(0, 3),
  CanonicalCell(1, 3),
  CanonicalCell(2, 3),
  CanonicalCell(3, 3),
  CanonicalCell(4, 3),
  CanonicalCell(0, 4),
  CanonicalCell(1, 4),
  CanonicalCell(2, 4),
  CanonicalCell(3, 4),
  CanonicalCell(4, 4),
];

/// Converts an absolute `ZoneCoord` (§3.1, catcher's view) into the
/// batter-relative frame the cells are indexed in.
///
/// Its own inverse — the mirror is an involution — so the same function
/// carries a relative point back out to absolute. Only x moves.
ZoneCoord relativeToBatter(ZoneCoord absolute, BatterSide side) => ZoneCoord(
  x: side == BatterSide.L ? -absolute.x : absolute.x,
  y: absolute.y,
);

/// The one cell containing [coord].
///
/// Total by construction — the partition covers the plane — which is what
/// §17.4 relies on to classify a freeform intent point or an actual location
/// however far off the plate it lands.
CanonicalCell cellContaining(ZoneCoord coord) =>
    canonicalCells.firstWhere((cell) => cell.bounds.contains(coord));
