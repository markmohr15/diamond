import 'dart:math' as math;
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/theme/brand_type.dart';
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
    this.origin,
    this.inMotion = false,
  });

  final String runnerId;

  /// The base the play found her on — the anchor an in-motion token
  /// renders back toward.
  final int? origin;

  /// True while her position is the play's presumption rather than the
  /// scorer's answer: she draws partway up the line (§15.1 v0.43).
  final bool inMotion;

  /// Short print label ("B" for the batter-runner, "1"/"2"/"3" for the base
  /// a runner started on) — tokens are position markers, never player names.
  final String label;

  /// 0 = batter's box (drawn beside the plate), 1–3 bases, 4 = scored
  /// (drawn at the plate, dimmed).
  final int base;
}

/// The field, §18.7-style: line work in ink, the play's data in accent, no
/// scenery. Fence from the spline, foul lines to the poles, basepath
/// diamond, circle, fielder spots — the stage; landing/roll end/runners —
/// the datum, which is where the accent goes.
class FieldPainter extends CustomPainter {
  FieldPainter({
    required this.geometry,
    required this.ink,
    required this.accent,
    required this.surface,
    this.landing,
    this.rollEnd,
    this.tokens = const [],
    this.dragPosition,
    this.dragTokenId,
    this.dragFielderPosition,
    this.holderPosition,
    this.movedFielders = const {},
    this.route = const [],
    this.forcePlayBase,
    this.canRecordOut = true,
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
  final FieldCoord? rollEnd;
  final List<RunnerToken> tokens;

  /// Live gesture state: where the active drag currently is, and — when the
  /// drag started on a runner token — whose. Null [dragTokenId] with a
  /// non-null [dragPosition] is a landing drag's roll preview.
  final Offset? dragPosition;
  final String? dragTokenId;

  /// The fielder currently in hand: she rides the finger (§15.1 v0.43 —
  /// wherever she is dropped is where the ball went).
  final int? dragFielderPosition;

  /// The position currently holding the ball, ringed in accent — where a
  /// throw drag starts (§15.1).
  final int? holderPosition;

  /// Where the fielder drag left fielders this play — overrides the
  /// standard spot for the positions it names.
  final Map<int, FieldCoord> movedFielders;

  /// A force play awaiting its answer: the SAFE/OUT pair renders at this
  /// base until the scorer taps one (§15.1 v0.43 — the throw arrived, the
  /// question is asked where it happened).
  final int? forcePlayBase;

  /// False once the half is over (§4.4's three outs): the pills lose their
  /// OUT half, because there is no fourth out to record.
  final bool canRecordOut;

  /// The ball's journey through the play, in order: where it ended up off
  /// the bat, then every touch location — throws included. Drawn as dashed
  /// accent segments so each tap visibly moves the ball from one spot to
  /// the next (§15.1 v0.43).
  final List<FieldCoord> route;

  static const double _tokenRadiusPx = 20;

  /// How close (px) a dragged runner must be to a base before its Safe/Out
  /// pair fades in (§15.1 v0.43).
  static const double approachRadiusPx = 110;

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
    _paintRoute(canvas);
    _paintBaseTargets(canvas);
    _paintTokens(canvas);
  }

  /// The ball's journey (§15.1 v0.43): dashed accent segments between
  /// consecutive touch points, so a throw reads as the ball moving.
  void _paintRoute(Canvas canvas) {
    if (route.length < 2) return;
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: 0.45);
    for (var i = 0; i < route.length - 1; i++) {
      _paintDashedLine(
        canvas,
        geometry.toPx(route[i]),
        geometry.toPx(route[i + 1]),
        paint,
      );
    }
  }

  void _paintDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 8.0;
    const gap = 6.0;
    final total = (to - from).distance;
    if (total < 1) return;
    final direction = (to - from) / total;
    var covered = 0.0;
    while (covered < total) {
      final end = (covered + dash).clamp(0.0, total);
      canvas.drawLine(
        from + direction * covered,
        from + direction * end,
        paint,
      );
      covered = end + gap;
    }
  }

  /// §15.1 v0.43's paired drop targets: as a dragged runner approaches a
  /// base, **Safe** and **Out** pills appear at that base — and only there,
  /// only then. GameChanger got this part right.
  void _paintBaseTargets(Canvas canvas) {
    final drag = dragPosition;
    final base =
        forcePlayBase ??
        (dragTokenId != null && drag != null
            ? geometry.nearestBaseWithin(drag, approachRadiusPx)
            : null);
    if (base == null) return;
    // Whichever pill the runner is over lights up — the same one the
    // release resolves to, so the canvas never shows one answer and
    // commits another.
    final hot = dragTokenId != null && drag != null
        ? geometry.pillAt(base, drag)
        : null;
    _paintPill(
      canvas,
      'SAFE',
      geometry.safeAffordanceCenter(base),
      lit: hot == BaseCall.safe,
    );
    if (canRecordOut) {
      _paintPill(
        canvas,
        'OUT',
        geometry.outAffordanceCenter(base),
        lit: hot == BaseCall.out,
      );
    }
  }

  void _paintPill(
    Canvas canvas,
    String text,
    Offset center, {
    bool lit = false,
  }) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 82, height: 40),
      const Radius.circular(20),
    );
    canvas
      ..drawRRect(rect, Paint()..color = lit ? accent : surface)
      ..drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lit ? 3 : 2
          ..color = lit ? accent : ink.withValues(alpha: 0.75),
      );
    _paintLabel(
      canvas,
      text,
      center,
      lit ? surface : ink,
      fontSize: 15,
      bold: true,
    );
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
      final inHand = entry.key == dragFielderPosition && dragPosition != null;
      final px = inHand
          ? dragPosition!
          : geometry.toPx(movedFielders[entry.key] ?? entry.value);
      canvas.drawCircle(px, 15, faint);
      // The ball's current holder: accent ring — the throw drag's grip.
      if (entry.key == holderPosition) {
        canvas.drawCircle(
          px,
          19,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = accent,
        );
      }
      _paintLabel(
        canvas,
        positionAbbreviations[entry.key] ?? '${entry.key}',
        px,
        ink.withValues(alpha: 0.55),
        fontSize: 11,
      );
    }
  }

  void _paintPlay(Canvas canvas) {
    final landing = this.landing;
    if (landing == null) {
      // Path press in progress with nothing committed yet: ghost at the
      // pointer. Never during a runner or fielder drag — those render
      // themselves.
      final drag = dragPosition;
      if (drag != null && dragTokenId == null && dragFielderPosition == null) {
        canvas.drawCircle(
          drag,
          8,
          Paint()..color = accent.withValues(alpha: 0.5),
        );
      }
      return;
    }

    final landingPx = geometry.toPx(landing);

    // The streak (§15.1 v0.43): first bounce → where it ended up, drawn in
    // accent so the ball's path reads at a glance.
    final rollEndPx = rollEnd == null ? null : geometry.toPx(rollEnd!);
    if (rollEndPx != null) {
      canvas
        ..drawLine(
          landingPx,
          rollEndPx,
          Paint()
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round
            ..color = accent.withValues(alpha: 0.6),
        )
        ..drawCircle(rollEndPx, 5, Paint()..color = accent);
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
          : geometry.runnerTokenCenter(
              base: token.base,
              origin: token.origin,
              inMotion: token.inMotion,
            );
      // Faded means *done* — she scored and the play no longer concerns
      // her. A runner still in motion at home has not: on a bases-loaded
      // ground ball the walk-up forces the runner from third all the way
      // home, and she is the one whose fate is least settled, not the most.
      // §15.1's rule is that "she's going there" and "she got there" stay
      // visually different until the scorer answers; fading on base alone
      // gave that answer a step early.
      final scored = token.base == 4 && !token.inMotion;
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

  /// The sizes callers pass here are **canvas geometry, not type scale**
  /// (§23.5 keeps the scale to prose and codes in widgets). Each is chosen to
  /// fit inside a shape this painter draws — an 82x40 pill, a 20px-radius
  /// token — so moving them onto a scale step would overflow the shape rather
  /// than restyle the text. §23's preamble is explicit that a design pass does
  /// not relitigate a derived value.
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
        // The one funnel for every string this painter draws, and all of
        // them are codes (§23.5): fielding positions, runner tokens, and the
        // OUT/SAFE pills. None is prose, so the face is set here rather than
        // at three call sites that could drift apart.
        //
        // w700 rather than w600: only 400/500/700 are bundled, and Flutter
        // resolves an unbundled weight to the nearest one silently — so w600
        // was already rendering as something else and calling it a choice.
        style: TextStyle(
          color: color,
          fontFamily: BrandType.mono,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
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
        oldDelegate.rollEnd != rollEnd ||
        oldDelegate.tokens != tokens ||
        oldDelegate.dragPosition != dragPosition ||
        oldDelegate.dragTokenId != dragTokenId ||
        oldDelegate.dragFielderPosition != dragFielderPosition ||
        oldDelegate.holderPosition != holderPosition ||
        oldDelegate.movedFielders != movedFielders ||
        oldDelegate.route != route ||
        oldDelegate.forcePlayBase != forcePlayBase ||
        oldDelegate.canRecordOut != canRecordOut ||
        oldDelegate.ink != ink ||
        oldDelegate.accent != accent ||
        oldDelegate.geometry.size != geometry.size;
  }
}
