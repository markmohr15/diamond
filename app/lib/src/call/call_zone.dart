import 'package:diamond/src/call/canonical_cells.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter/foundation.dart';

/// A call zone (§10.1): a named **grouping** of canonical cells, never an
/// independently authored rectangle.
///
/// `bounds` and `centroid` are derived from the member cells, which is what
/// makes overlapping zones and uncovered gaps unrepresentable rather than
/// merely invalid — see [CallZoneLayout].
@immutable
class CallZone {
  const CallZone({required this.id, required this.label, required this.cells});

  final String id;

  /// Coach-facing, and **batter-relative** where it says "in" or "away"
  /// (§10.1's vocabulary). The geometry underneath is absolute (§3.1).
  final String label;

  final List<CanonicalCell> cells;

  /// The union's extent. Unbounded whenever any member cell is, which is the
  /// normal case for a zone touching the ring.
  ///
  /// Used only by the test suite. Nothing in production wants a zone's extent:
  /// classification goes through [contains]/[CallZoneLayout.zoneFor] and the
  /// render goes through [nominalBounds], precisely because this rect is
  /// usually infinite.
  ZoneRect get bounds {
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final cell in cells) {
      final b = cell.bounds;
      if (b.minX < minX) minX = b.minX;
      if (b.maxX > maxX) maxX = b.maxX;
      if (b.minY < minY) minY = b.minY;
      if (b.maxY > maxY) maxY = b.maxY;
    }
    return ZoneRect(minX: minX, maxX: maxX, minY: minY, maxY: maxY);
  }

  /// The target stored as `PitchThrown.intendedLocation` (§10.1).
  ///
  /// The mean of the member cells' nominal centroids — deliberately **not** the
  /// geometric centroid of [bounds], which is undefined the moment a ring cell
  /// is included. A grouped "chase high" therefore targets the middle of the
  /// cells it groups, exactly as a single-cell zone targets its own.
  ZoneCoord get centroid {
    var sumX = 0.0;
    var sumY = 0.0;
    for (final cell in cells) {
      sumX += cell.centroid.x;
      sumY += cell.centroid.y;
    }
    return ZoneCoord(x: sumX / cells.length, y: sumY / cells.length);
  }

  /// The rect this zone *draws* as (§11.4): one strike-zone cell centered on
  /// [centroid], whatever the zone's true extent.
  ///
  /// Not [bounds], which is what a pitch is classified against and runs to
  /// infinity for any zone touching the ring — a swatch covering half the
  /// canvas would say the zone is enormous when what it means is "off the plate
  /// this way." Not one rect per member cell either: a grouped zone is a single
  /// call with a single code, and painting its cells separately shows several
  /// targets where there is one.
  ZoneRect get nominalBounds => ZoneRect.nominalCellAround(centroid);

  /// [centroid] resolved into the absolute frame for the batter in the box —
  /// what `PitchThrown.intendedLocation` stores (§10.1). Mirroring the mean is
  /// the same as the mean of the mirrored cells, since the mirror is linear.
  ZoneCoord absoluteCentroid(BatterSide side) {
    final relative = centroid;
    return ZoneCoord(
      x: side == BatterSide.L ? -relative.x : relative.x,
      y: relative.y,
    );
  }

  /// Whether this is a call for a ball (§10.1): derived from where the centroid
  /// sits, never stored. Nobody calls a location inside the zone hoping for a
  /// ball, so an `objective` field would be redundant state that could
  /// contradict the geometry.
  bool get isChase =>
      centroid.x < -1 || centroid.x > 1 || centroid.y < 0 || centroid.y > 1;

  /// Whether [coord] resolves to this zone (§17.4).
  ///
  /// Used only by the test suite, where it states the partition invariant one
  /// zone at a time. Production asks the layout instead —
  /// [CallZoneLayout.zoneFor] answers the same question without scanning zones
  /// that cannot own the point.
  bool contains(ZoneCoord coord) => cells.contains(cellContaining(coord));

  @override
  String toString() => 'CallZone($id, ${cells.length} cells)';
}

/// A team's layout: a partition of all 25 canonical cells into call zones.
///
/// The invariant is checked at construction rather than trusted, because
/// everything downstream assumes it: §17.4 resolves any point — a freeform
/// intent tap, an actual location, an observation-mode pitch against a layout
/// that isn't yours — to exactly one zone.
@immutable
class CallZoneLayout {
  factory CallZoneLayout({required String id, required List<CallZone> zones}) {
    final seen = <String, String>{};
    for (final zone in zones) {
      if (zone.cells.isEmpty) {
        throw ArgumentError('zone "${zone.id}" owns no cells');
      }
      for (final cell in zone.cells) {
        final existing = seen[cell.id];
        if (existing != null) {
          throw ArgumentError(
            'cell ${cell.id} is claimed by both "$existing" and "${zone.id}" '
            '— zones may not overlap',
          );
        }
        seen[cell.id] = zone.id;
      }
    }
    final missing = canonicalCells
        .where((cell) => !seen.containsKey(cell.id))
        .map((cell) => cell.id)
        .toList();
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'layout leaves ${missing.length} cell(s) uncovered: '
        '${missing.join(", ")} — every point must resolve to a zone',
      );
    }
    return CallZoneLayout._(id: id, zones: zones);
  }

  const CallZoneLayout._({required this.id, required this.zones});

  final String id;
  final List<CallZone> zones;

  /// The zone owning [coord]. Total, by the constructor's invariant.
  CallZone zoneFor(ZoneCoord coord) {
    final cell = cellContaining(coord);
    return zones.firstWhere((zone) => zone.cells.contains(cell));
  }

  CallZone? byId(String zoneId) {
    for (final zone in zones) {
      if (zone.id == zoneId) return zone;
    }
    return null;
  }
}
