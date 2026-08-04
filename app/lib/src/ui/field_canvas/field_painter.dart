import 'dart:math' as math;

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:flutter/material.dart';

/// One runner as the canvas shows them: who, what to print on the token,
/// and where they currently stand — draft moves already applied by the
/// surface, so the painter only ever renders, never reasons.
@immutable
class RunnerToken {
  const RunnerToken({
    required this.runnerId,
    required this.label,
    required this.base,
  });

  final String runnerId;

  /// Short print label ("B" for the batter-runner, "1"/"2"/"3" for the base
  /// a runner started on) — tokens are position markers, never player names.
  final String label;

  /// 0 = batter's box (drawn beside the plate), 1–3 bases, 4 = scored
  /// (drawn at the plate, dimmed).
  final int base;
}

/// The field, §18.7-style: line work in ink, the play's data in accent, no
/// scenery. Fence from the spline, foul lines to the poles, basepath
/// diamond, circle, fielder spots — the stage; landing/retrieved/runners —
/// the datum, which is where the accent goes.
class FieldPainter extends CustomPainter {
  FieldPainter({
    required this.geometry,
    required this.ink,
    required this.accent,
    required this.surface,
    this.landing,
    this.retrieved,
    this.tokens = const [],
    this.dragPosition,
    this.dragTokenId,
  });

  final FieldGeometry geometry;

  /// Line-work color (`onSurface`); structural strokes take alphas of it.
  final Color ink;

  /// `colorScheme.primary`, on the datum only (§18.7): landing, roll,
  /// runner tokens in motion.
  final Color accent;

  /// Token text color against [accent] fills.
  final Color surface;

  final FieldCoord? landing;
  final FieldCoord? retrieved;
  final List<RunnerToken> tokens;

  /// Live gesture state: where the active drag currently is, and — when the
  /// drag started on a runner token — whose. Null [dragTokenId] with a
  /// non-null [dragPosition] is a landing drag's roll preview.
  final Offset? dragPosition;
  final String? dragTokenId;

  static const double _tokenRadiusPx = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final structural = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ink.withValues(alpha: 0.55);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ink.withValues(alpha: 0.3);

    _paintFence(canvas, structural);
    _paintFoulLines(canvas, structural);
    _paintInfield(canvas, structural, faint);
    _paintFielders(canvas, faint);
    _paintPlay(canvas);
    _paintTokens(canvas);
  }

  void _paintFence(Canvas canvas, Paint paint) {
    const samples = 64;
    const thetaMin = -math.pi / 4;
    final path = Path();
    for (var i = 0; i <= samples; i++) {
      final theta = thetaMin + (i / samples) * (2 * -thetaMin);
      final r = geometry.profile.fenceDistanceAt(theta);
      final px = geometry.toPx(_polar(theta, r));
      if (i == 0) {
        path.moveTo(px.dx, px.dy);
      } else {
        path.lineTo(px.dx, px.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _paintFoulLines(Canvas canvas, Paint paint) {
    final plate = geometry.plate;
    for (final side in const [-1, 1]) {
      final theta = side * math.pi / 4;
      final end = geometry.toPx(
        _polar(theta, geometry.profile.fenceDistanceAt(theta)),
      );
      canvas.drawLine(plate, end, paint);
    }
  }

  void _paintInfield(Canvas canvas, Paint structural, Paint faint) {
    // Basepath diamond.
    final diamond = Path()
      ..moveTo(geometry.plate.dx, geometry.plate.dy)
      ..lineTo(geometry.baseCenter(1).dx, geometry.baseCenter(1).dy)
      ..lineTo(geometry.baseCenter(2).dx, geometry.baseCenter(2).dy)
      ..lineTo(geometry.baseCenter(3).dx, geometry.baseCenter(3).dy)
      ..close();
    canvas.drawPath(diamond, structural);

    // Bases as filled squares rotated to the diamond's orientation; the
    // plate gets a hollow marker of the same size. Drawn oversized (a real
    // base is 15″) — they are drag targets and landmarks, not scale scenery.
    final baseFill = Paint()..color = ink.withValues(alpha: 0.55);
    final half = 2.5 * geometry.pxPerFoot;
    for (var base = 1; base <= 3; base++) {
      final c = geometry.baseCenter(base);
      final square = Path()
        ..moveTo(c.dx, c.dy - half)
        ..lineTo(c.dx + half, c.dy)
        ..lineTo(c.dx, c.dy + half)
        ..lineTo(c.dx - half, c.dy)
        ..close();
      canvas.drawPath(square, baseFill);
    }

    // Plate marker, and the pitcher's circle: 8 ft radius, honest enough at
    // canvas scale (the rubber-tangent detail reads as noise this small).
    canvas
      ..drawCircle(geometry.plate, half, faint)
      ..drawCircle(
        geometry.toPx(FieldCoord(x: 0, y: geometry.profile.pitchingDistance)),
        8 * geometry.pxPerFoot,
        faint,
      );
  }

  void _paintFielders(Canvas canvas, Paint faint) {
    final spots = standardFielderSpots(geometry.profile);
    for (final entry in spots.entries) {
      final px = geometry.toPx(entry.value);
      canvas.drawCircle(px, 15, faint);
      _paintLabel(
        canvas,
        '${entry.key}',
        px,
        ink.withValues(alpha: 0.55),
        fontSize: 13,
      );
    }
  }

  void _paintPlay(Canvas canvas) {
    final landing = this.landing;
    if (landing == null) {
      // Landing drag in progress with nothing committed yet: ghost at the
      // pointer.
      final drag = dragPosition;
      if (drag != null && dragTokenId == null) {
        canvas.drawCircle(
          drag,
          8,
          Paint()..color = accent.withValues(alpha: 0.5),
        );
      }
      return;
    }

    final landingPx = geometry.toPx(landing);

    // The roll: landing → retrieved (or → live drag position).
    final rollEnd = retrieved != null
        ? geometry.toPx(retrieved!)
        : (dragTokenId == null ? dragPosition : null);
    if (rollEnd != null) {
      canvas
        ..drawLine(
          landingPx,
          rollEnd,
          Paint()
            ..strokeWidth = 2
            ..color = accent.withValues(alpha: 0.6),
        )
        ..drawCircle(rollEnd, 5, Paint()..color = accent);
    }

    // The landing itself: the spray-chart point, the datum of the play.
    canvas
      ..drawCircle(landingPx, 7, Paint()..color = accent)
      ..drawCircle(
        landingPx,
        12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent.withValues(alpha: 0.5),
      );
  }

  void _paintTokens(Canvas canvas) {
    for (final token in tokens) {
      final dragging = token.runnerId == dragTokenId;
      final center = dragging && dragPosition != null
          ? dragPosition!
          : geometry.tokenCenter(token.base);
      final scored = token.base == 4;
      final fill = Paint()
        ..color = dragging
            ? accent
            : (scored
                  ? ink.withValues(alpha: 0.25)
                  : ink.withValues(alpha: 0.75));
      canvas.drawCircle(center, _tokenRadiusPx, fill);
      _paintLabel(
        canvas,
        token.label,
        center,
        surface,
        fontSize: 14,
        bold: true,
      );
    }
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset center,
    Color color, {
    required double fontSize,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  /// FieldCoord bearing convention (§3.2): x = r·sinθ, y = r·cosθ.
  static FieldCoord _polar(double theta, double r) =>
      FieldCoord(x: r * math.sin(theta), y: r * math.cos(theta));

  @override
  bool shouldRepaint(FieldPainter oldDelegate) {
    return oldDelegate.landing != landing ||
        oldDelegate.retrieved != retrieved ||
        oldDelegate.tokens != tokens ||
        oldDelegate.dragPosition != dragPosition ||
        oldDelegate.dragTokenId != dragTokenId ||
        oldDelegate.ink != ink ||
        oldDelegate.accent != accent ||
        oldDelegate.geometry.size != geometry.size;
  }
}
