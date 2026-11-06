import 'dart:math' as math;
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/theme/brand_baseline.dart';
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
    required this.onAccent,
    required this.seam,
    this.landing,
    this.rollEnd,
    this.tokens = const [],
    this.dragPosition,
    this.dragTokenId,
    this.dragFielderPosition,
    this.holderPosition,
    this.ballAt,
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

  /// Label color on an [accent] fill (`colorScheme.onPrimary`, which
  /// `deriveScheme` picks by contrast against the accent itself).
  final Color onAccent;

  /// The ball's seams: Clay as line (`DiamondSemantics.clayLine`), which
  /// never moves with a team accent (§23.3).
  final Color seam;

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

  /// The position currently holding the ball — where a throw drag starts
  /// (§15.1). Her token is the one filled on the field.
  final int? holderPosition;

  /// Where the ball is (`PlayDraft.ballAt`). With no [holderPosition] it is
  /// drawn **loose** here; null draws no ball at all, which is the case
  /// between pitches when the pitch got past the catcher and nobody has
  /// said where it went.
  final FieldCoord? ballAt;

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

  /// Fielder tokens, and the holder's one size up (§15.1 v0.62): the step
  /// 14A draws as 64 against 54, applied to the surface's own size.
  static const double _fielderRadiusPx = 15;
  static const double _holderRadiusPx = 18;

  /// The ball glyph, and the dashed ground ring a loose ball sits in.
  static const double _ballRadiusPx = 6.5;
  static const double _looseRingRadiusPx = 10;

  /// How close the ball must lie to a fielder's token to be drawn *at her
  /// feet* — over her token's lower edge — rather than in the open.
  static const double _atFeetPx = _fielderRadiusPx + 6;

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
    _paintLooseBall(canvas);
    // After the play's own marks: a ball caught where it landed puts the
    // landing marker on her spot, and it must not cover her label.
    _paintHolder(canvas);
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
      lit ? onAccent : ink,
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

  /// Where a fielder renders right now: on the finger while she is in hand,
  /// else where this play moved her, else her standard spot.
  Map<int, Offset> _fielderCenters() {
    return {
      for (final entry in standardFielderSpots(geometry.profile).entries)
        entry.key: entry.key == dragFielderPosition && dragPosition != null
            ? dragPosition!
            : geometry.toPx(movedFielders[entry.key] ?? entry.value),
    };
  }

  void _paintFielders(Canvas canvas, Paint faint) {
    for (final MapEntry(key: position, value: px)
        in _fielderCenters().entries) {
      if (position == holderPosition) continue;
      canvas.drawCircle(px, _fielderRadiusPx, faint);
      _paintLabel(
        canvas,
        positionAbbreviations[position] ?? '$position',
        px,
        ink.withValues(alpha: 0.55),
        fontSize: 11,
      );
    }
  }

  void _paintHolder(Canvas canvas) {
    final position = holderPosition;
    final px = position == null ? null : _fielderCenters()[position];
    if (position == null || px == null) return;
    final label = positionAbbreviations[position] ?? '$position';
    // Who has the ball, three ways at once and none of them motion
    // (§15.1 v0.60): the only filled token on the field, a heavy ink ring
    // and one size up; the ball seated in her rim; HAS BALL beneath. Fill
    // against outline and ink against nothing are differences of value, not
    // hue, so they survive glare and grayscale.
    canvas
      ..drawCircle(px, _holderRadiusPx, Paint()..color = accent)
      ..drawCircle(
        px,
        _holderRadiusPx,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ink,
      );
    _paintLabel(canvas, label, px, onAccent, fontSize: 12, bold: true);
    const rim = _holderRadiusPx * math.sqrt1_2;
    _paintBall(canvas, px + const Offset(rim, -rim), ring: ink);
    _paintTag(canvas, 'HAS BALL', _below(px, _holderRadiusPx), solid: true);
  }

  /// A loose ball (§15.1 v0.60) is a different object, not a weaker holder:
  /// the ball in a dashed ground ring with a dashed LOOSE tag, and every
  /// token left neutral. Nothing to draw while someone holds it — the ball
  /// rides her token — or once it is over the fence and out of play.
  void _paintLooseBall(Canvas canvas) {
    final at = ballAt;
    if (at == null || holderPosition != null) return;
    if (FieldGeometry.isFair(at) && geometry.fenceDepthFt(at) < 0) return;
    var center = geometry.toPx(at);
    // At a fielder's feet — a boot, a deflection, "missed it" where she was
    // dropped — the ball sits over her token's lower edge, so *the ball is
    // here* and *she has it* stay distinct at zero separation (§15.1). Her
    // label stays clear above it.
    for (final px in _fielderCenters().values) {
      if ((px - center).distance <= _atFeetPx) {
        center = px + const Offset(0, _fielderRadiusPx + 2);
        break;
      }
    }
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ink.withValues(alpha: 0.75);
    canvas
      ..drawCircle(center, _looseRingRadiusPx, Paint()..color = surface)
      ..drawPath(
        _dashed(
          Path()..addOval(
            Rect.fromCircle(center: center, radius: _looseRingRadiusPx),
          ),
          dash: 4,
          gap: 3,
        ),
        ringPaint,
      );
    _paintBall(canvas, center, ring: ink.withValues(alpha: 0.75));
    _paintTag(canvas, 'LOOSE', _below(center, _looseRingRadiusPx));
  }

  /// The ball glyph: Chalk with Clay seams in both themes, since a ball is
  /// white whatever the screen is doing.
  void _paintBall(Canvas canvas, Offset center, {required Color ring}) {
    const r = _ballRadiusPx;
    canvas
      ..drawCircle(center, r, Paint()..color = BrandBaseline.onBrandFill)
      ..drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ring,
      );
    final seams = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = seam;
    for (final side in const [-1.0, 1.0]) {
      canvas.drawArc(
        Rect.fromCircle(
          center: center + Offset(side * r * 1.15, 0),
          radius: r * 0.85,
        ),
        side < 0 ? -math.pi / 3 : math.pi * 2 / 3,
        math.pi * 2 / 3,
        false,
        seams,
      );
    }
  }

  /// Where a tag beneath something of [radius] centers — flipped above it
  /// when beneath would leave the canvas, as it can for the catcher.
  Offset _below(Offset center, double radius) {
    const gap = 4.0;
    const half = _tagHeightPx / 2;
    final under = center.dy + radius + gap + half;
    final dy = under + half <= geometry.size.height
        ? under
        : center.dy - radius - gap - half;
    return Offset(center.dx, dy);
  }

  static const double _tagHeightPx = 16;

  /// A small mono tag. [solid] is Ink with Chalk text (HAS BALL); otherwise
  /// a dashed outline (LOOSE), matching the dashed ring it labels.
  void _paintTag(
    Canvas canvas,
    String text,
    Offset center, {
    bool solid = false,
  }) {
    final width = 9.0 + text.length * 6.4;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: _tagHeightPx),
      const Radius.circular(4),
    );
    if (solid) {
      canvas.drawRRect(rect, Paint()..color = ink);
    } else {
      canvas
        ..drawRRect(rect, Paint()..color = surface)
        ..drawPath(
          _dashed(Path()..addRRect(rect), dash: 4, gap: 3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = ink.withValues(alpha: 0.75),
        );
    }
    _paintLabel(
      canvas,
      text,
      center,
      solid ? surface : ink,
      fontSize: 9.5,
      bold: true,
    );
  }

  /// [source] cut into dashes along its length.
  static Path _dashed(
    Path source, {
    required double dash,
    required double gap,
  }) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        out.addPath(metric.extractPath(d, d + dash), Offset.zero);
        d += dash + gap;
      }
    }
    return out;
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
        // On the accent while she is in hand, so its on-color; `surface` is
        // dark after dark and vanished against the fill.
        dragging ? onAccent : surface,
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
        oldDelegate.ballAt != ballAt ||
        oldDelegate.onAccent != onAccent ||
        oldDelegate.seam != seam ||
        oldDelegate.movedFielders != movedFielders ||
        oldDelegate.route != route ||
        oldDelegate.forcePlayBase != forcePlayBase ||
        oldDelegate.canRecordOut != canRecordOut ||
        oldDelegate.ink != ink ||
        oldDelegate.accent != accent ||
        oldDelegate.geometry.size != geometry.size;
  }
}
