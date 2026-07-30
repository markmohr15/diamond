import 'package:diamond/src/call/call_zone.dart';
import 'package:diamond/src/call/canonical_cells.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/material.dart';

/// Draws §10.1's call zones over the entry canvas (§11.4, v0.38).
///
/// The grid lives *on* the canvas rather than beside it: the canvas already
/// spans x ∈ [±4.0] and y ∈ [−1.05, 1.5], which is exactly where the ring cells
/// sit, so the 3×3 lands inside the zone rect and the ring fills the space
/// around it. The coach calls and records on the same picture.
///
/// Geometry never mirrors (§11.4). Cells are indexed batter-relative, so what
/// moves with handedness is which side of the canvas a cell is *drawn* on —
/// "inside" is negative x for a righty — not the canvas itself.
class CallGridPainter extends CustomPainter {
  const CallGridPainter({
    required this.layout,
    required this.callableZoneIds,
    required this.selectedZoneId,
    required this.batterSide,
    required this.callableFill,
    required this.accent,
  });

  final CallZoneLayout layout;

  /// Zones offerable for the pitch type currently selected. Everything else
  /// goes quiet — the call screen never offers a call the active card cannot
  /// express (§10.1).
  final Set<String> callableZoneIds;

  final String? selectedZoneId;
  final BatterSide batterSide;

  /// Marks a zone as available to call — green, from
  /// `DiamondSemantics.callable`. Zones that are *not* callable are simply not
  /// drawn: absence is the quietest possible treatment, and it leaves the
  /// ground furniture underneath unobscured.
  final Color callableFill;

  /// The one zone already chosen (§23.1.3 — the accent goes to the datum).
  final Color accent;

  double _absoluteX(double relativeX) =>
      batterSide == BatterSide.L ? -relativeX : relativeX;

  /// One swatch per zone, always the size of one of the nine strike-zone
  /// cells, centered on the zone's target.
  ///
  /// Deliberately **not** one block per member cell. A grouped "chase up" is a
  /// single call with a single code, so painting its five cells separately
  /// would show five targets where there is one — and with three grouped chase
  /// zones on the card that lights most of the canvas, which reads as
  /// "everything is available" and tells the coach nothing.
  ///
  /// The swatch is the indicator, not the hit area: the zone still owns
  /// everything its cells cover, so a tap well off the plate lands correctly
  /// (§17.4 containment) even though the green mark beside the plate is small.
  Rect _zoneRect(CallZone zone, Size size) {
    final centroid = zone.centroid;
    final left = _absoluteX(centroid.x - CanonicalCell.columnWidth / 2);
    final right = _absoluteX(centroid.x + CanonicalCell.columnWidth / 2);
    return Rect.fromPoints(
      localFromZoneCoord(
        ZoneCoord(
          x: left < right ? left : right,
          y: centroid.y + CanonicalCell.rowHeight / 2,
        ),
        size,
      ),
      localFromZoneCoord(
        ZoneCoord(
          x: left < right ? right : left,
          y: centroid.y - CanonicalCell.rowHeight / 2,
        ),
        size,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Only what can be called is drawn. No dividing lines: the canvas already
    // carries the zone rect and its 3x3, and a second grid over the top of the
    // ground furniture was ink competing with the markers rather than carrying
    // information (§23.1.1).
    for (final zone in layout.zones) {
      if (!callableZoneIds.contains(zone.id) || zone.id == selectedZoneId) {
        continue;
      }
      final rect = _zoneRect(zone, size);
      canvas
        ..drawRect(rect, Paint()..color = callableFill.withValues(alpha: 0.22))
        ..drawRect(
          rect,
          Paint()
            ..color = callableFill.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }

    // The accent goes to the datum (§23.1.3): the one zone chosen, drawn last
    // so it reads over the field of available ones.
    final selected = selectedZoneId;
    if (selected != null) {
      final zone = layout.byId(selected);
      if (zone != null) {
        final rect = _zoneRect(zone, size);
        canvas
          ..drawRect(rect, Paint()..color = accent.withValues(alpha: 0.30))
          ..drawRect(
            rect,
            Paint()
              ..color = accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CallGridPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.selectedZoneId != selectedZoneId ||
      oldDelegate.batterSide != batterSide ||
      oldDelegate.callableZoneIds != callableZoneIds ||
      oldDelegate.accent != accent ||
      oldDelegate.callableFill != callableFill;
}
