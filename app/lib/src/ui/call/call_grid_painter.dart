import 'package:diamond/src/call/call_zone.dart';
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
    required this.callableOutline,
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
  /// The wash and its border (§23.2 v0.47). Both arrive at their final
  /// opacity — Grass at 14/18% and 34/42% — so this paints them as given.
  /// Multiplying an alpha here again would compound with the token and put
  /// the wash back under the threshold where it reads as a smudge.
  final Color callableFill;
  final Color callableOutline;

  /// The one zone already chosen (§23.1.3 — the accent goes to the datum).
  final Color accent;

  double _absoluteX(double relativeX) =>
      batterSide == BatterSide.L ? -relativeX : relativeX;

  /// [CallZone.nominalBounds] mirrored for the batter in the box and projected
  /// to the canvas — the model decides the swatch's size and where it sits, and
  /// this decides only which way "in" faces.
  ///
  /// The swatch is the indicator, not the hit area: the zone still owns
  /// everything its cells cover, so a tap well off the plate lands correctly
  /// (§17.4 containment) even though the green mark beside the plate is small.
  Rect _zoneRect(CallZone zone, Size size) {
    final nominal = zone.nominalBounds;
    // Mirroring negates x, so the min and max edges swap for a lefty.
    final left = _absoluteX(nominal.minX);
    final right = _absoluteX(nominal.maxX);
    return Rect.fromPoints(
      localFromZoneCoord(
        ZoneCoord(x: left < right ? left : right, y: nominal.maxY),
        size,
      ),
      localFromZoneCoord(
        ZoneCoord(x: left < right ? right : left, y: nominal.minY),
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
        ..drawRect(rect, Paint()..color = callableFill)
        ..drawRect(
          rect,
          Paint()
            ..color = callableOutline
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
