import 'package:diamond/src/call/call_zone.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:material_ui/material_ui.dart';

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
    this.offOutline,
  });

  final CallZoneLayout layout;

  /// Zones offerable for the pitch type currently selected. Everything else
  /// goes quiet — the call screen never offers a call the active card cannot
  /// express (§10.1).
  final Set<String> callableZoneIds;

  final String? selectedZoneId;
  final BatterSide batterSide;

  /// Marks a zone as available to call — green, from
  /// `DiamondSemantics.callable`. A ring zone that is *not* callable is simply
  /// not drawn: absence is the quietest possible treatment, and it leaves the
  /// ground furniture underneath unobscured. An in-zone one is dashed
  /// ([offOutline]).
  /// The wash and its border (§23.2 v0.47). Both arrive at their final
  /// opacity — §23.2's figures, Grass in light and Grass-as-line in dark —
  /// so this paints them as given.
  /// Multiplying an alpha here again would compound with the token and put
  /// the wash back under the threshold where it reads as a smudge.
  final Color callableFill;
  final Color callableOutline;

  /// The one zone already chosen (§23.1.3 — the accent goes to the datum),
  /// filled solid: §23.2's *called* step.
  final Color accent;

  /// §23.2's *off* step: the dashed edge of an in-zone cell the pitch in hand
  /// cannot be called to. Null draws none — before a pitch is picked nothing
  /// is callable *or* off, and dashing the whole zone would say "nothing can
  /// be called here" when what is true is "pick a pitch first."
  final Color? offOutline;

  /// Gap between a spot and the cell it sits in, so neighboring spots read
  /// as separate targets rather than one shaded block (15A).
  static const double _inset = 3;
  static const Radius _corner = Radius.circular(4);

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

  RRect _spot(CallZone zone, Size size) =>
      RRect.fromRectAndRadius(_zoneRect(zone, size).deflate(_inset), _corner);

  @override
  void paint(Canvas canvas, Size size) {
    // §23.2's three steps on one hue: wash = callable, solid = called,
    // dashed = off. A ring cell that is not callable is simply not drawn —
    // off the plate, absence already says it, and it leaves the ground
    // furniture underneath unobscured. No dividing lines either: the canvas
    // carries the zone rect and its 3x3 (§23.1.1).
    final wash = Paint()..color = callableFill;
    final washEdge = Paint()
      ..color = callableOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final off = offOutline;
    for (final zone in layout.zones) {
      if (zone.id == selectedZoneId) continue;
      final spot = _spot(zone, size);
      if (callableZoneIds.contains(zone.id)) {
        canvas
          ..drawRRect(spot, wash)
          ..drawRRect(spot, washEdge);
      } else if (off != null && !zone.isChase) {
        canvas.drawPath(
          _dashed(Path()..addRRect(spot)),
          Paint()
            ..color = off
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // The accent goes to the datum (§23.1.3): the one zone chosen, solid,
    // drawn last so it reads over the field of available ones.
    final zone = selectedZoneId == null ? null : layout.byId(selectedZoneId!);
    if (zone != null) {
      canvas.drawRRect(_spot(zone, size), Paint()..color = accent);
    }
  }

  /// [source] as 6-on, 5-off dashes (15A).
  static Path _dashed(Path source) {
    const dash = 6.0;
    const gap = 5.0;
    final out = Path();
    for (final metric in source.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        out.addPath(metric.extractPath(d, d + dash), Offset.zero);
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant CallGridPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.selectedZoneId != selectedZoneId ||
      oldDelegate.batterSide != batterSide ||
      oldDelegate.callableZoneIds != callableZoneIds ||
      oldDelegate.accent != accent ||
      oldDelegate.callableFill != callableFill ||
      oldDelegate.callableOutline != callableOutline ||
      oldDelegate.offOutline != offOutline;
}
