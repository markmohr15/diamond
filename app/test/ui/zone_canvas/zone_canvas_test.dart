import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Box the widget is given. The canvas aspect-fits inside it and the control
// strip sits below, so the painted drawing area is smaller than this — tests
// resolve coordinates against [zoneCanvasDrawingAreaKey] rather than assuming
// the two coincide.
const _harnessSize = Size(360, 560);

class _Harness extends StatefulWidget {
  const _Harness({
    this.mode = ZoneCanvasIntent.actual,
    this.underlay,
    this.onCommit,
    this.onSkip,
    this.onCancel,
    this.onCommitBounce,
    this.canCaptureBounce = false,
  });

  final ZoneCanvasIntent mode;
  final Widget? underlay;
  final ValueChanged<ZoneCoord>? onCommit;
  final VoidCallback? onSkip;
  final VoidCallback? onCancel;
  final ValueChanged<BounceCoord>? onCommitBounce;

  /// Whether the canvas is given an `onCommitBounce` at all — which is what
  /// enables the hinge. Defaults to off so the pre-hinge tests keep asserting
  /// the pre-hinge behaviour they were written for. Passing [onCommitBounce]
  /// implies it.
  final bool canCaptureBounce;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  ZoneCoord? value;
  BounceCoord? bounceValue;

  @override
  Widget build(BuildContext context) {
    final bounceEnabled =
        widget.canCaptureBounce || widget.onCommitBounce != null;
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _harnessSize.width,
            height: _harnessSize.height,
            child: ZoneCanvas(
              mode: widget.mode,
              value: value,
              bounceValue: bounceValue,
              underlay: widget.underlay,
              onCommit: (coord) {
                setState(() {
                  value = coord;
                  bounceValue = null;
                });
                widget.onCommit?.call(coord);
              },
              onCommitBounce: bounceEnabled
                  ? (bounce) {
                      setState(() {
                        bounceValue = bounce;
                        value = null;
                      });
                      widget.onCommitBounce?.call(bounce);
                    }
                  : null,
              onSkip: widget.onSkip ?? () {},
              onCancel: widget.onCancel ?? () {},
            ),
          ),
        ),
      ),
    );
  }
}

/// A callback that does nothing, for canvases built outside [_Harness] where
/// the test only cares about what renders.
void _noop(Object? _) {}
void _noopVoid() {}

/// The painted canvas rect — excludes the control strip (§11.4 moved Cancel and
/// skip-location outside the drawing area).
Rect _canvasRect(WidgetTester tester) =>
    tester.getRect(find.byKey(zoneCanvasDrawingAreaKey));

Offset _global(WidgetTester tester, Offset local) =>
    _canvasRect(tester).topLeft + local;

/// A point at the given fraction across the drawing area.
Offset _atFraction(WidgetTester tester, double fx, double fy) {
  final size = _canvasRect(tester).size;
  return Offset(size.width * fx, size.height * fy);
}

/// Long-press at [local] (drawing-area coordinates), optionally drag to
/// [moveTo], then release — the gesture the widget expects for commit/cancel.
Future<void> _longPressDragRelease(
  WidgetTester tester, {
  required Offset local,
  Offset? moveTo,
}) async {
  final gesture = await tester.startGesture(_global(tester, local));
  await tester.pump(zoneCanvasArmDuration + const Duration(milliseconds: 50));
  if (moveTo != null) {
    await gesture.moveTo(_global(tester, moveTo));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  // Pure conversion-function tests. The mapping is a plain scale-and-shift over
  // the canvas extents, so any size exercises it; these need no widget at all.
  group('zoneCoordFromLocal / localFromZoneCoord math', () {
    const size = Size(304, 644);

    test('drawing-area center maps to the mid-extent, (0, 0.225)', () {
      final coord = zoneCoordFromLocal(
        Offset(size.width / 2, size.height / 2),
        size,
      );
      expect(coord.x, closeTo(0, 1e-9));
      // (1.50 + -1.05) / 2 — below the zone's own center, since the extent
      // reaches down past the plate and the top is trimmed (§11.4).
      expect(
        coord.y,
        closeTo((zoneCanvasExtentMaxY + zoneCanvasExtentMinY) / 2, 1e-9),
      );
      expect(coord.y, closeTo(0.225, 1e-9));
    });

    test('top-left local origin maps to the min-x/max-y extreme', () {
      final coord = zoneCoordFromLocal(Offset.zero, size);
      expect(coord.x, closeTo(zoneCanvasExtentMinX, 1e-9));
      expect(coord.y, closeTo(zoneCanvasExtentMaxY, 1e-9));
    });

    test('bottom-right local corner maps to the max-x/min-y extreme', () {
      final coord = zoneCoordFromLocal(Offset(size.width, size.height), size);
      expect(coord.x, closeTo(zoneCanvasExtentMaxX, 1e-9));
      expect(coord.y, closeTo(zoneCanvasExtentMinY, 1e-9));
    });

    test('a point above the zone rect is out-of-zone but in-range (y > 1)', () {
      final coord = zoneCoordFromLocal(Offset(size.width / 2, 30), size);
      expect(coord.y, greaterThan(zoneMaxY));
      expect(coord.y, lessThanOrEqualTo(zoneCanvasExtentMaxY));
    });

    test('the extent reaches below the ground line, into the dirt band', () {
      const geometry = FrontalGeometry();
      final bottom = zoneCoordFromLocal(
        Offset(size.width / 2, size.height),
        size,
      );
      expect(bottom.y, lessThan(geometry.groundY));
    });

    test('localFromZoneCoord is the inverse of zoneCoordFromLocal', () {
      const local = Offset(77, 133);
      final coord = zoneCoordFromLocal(local, size);
      final roundTripped = localFromZoneCoord(coord, size);
      expect(roundTripped.dx, closeTo(local.dx, 1e-9));
      expect(roundTripped.dy, closeTo(local.dy, 1e-9));
    });
  });

  group('ZoneCanvas gesture semantics', () {
    testWidgets('long-press-release at the drawing-area center commits '
        '(0, 0.225)', (tester) async {
      ZoneCoord? committed;
      await tester.pumpWidget(_Harness(onCommit: (c) => committed = c));

      await _longPressDragRelease(tester, local: _atFraction(tester, 0.5, 0.5));

      expect(committed, isNotNull);
      expect(committed!.x, closeTo(0, 1e-6));
      expect(committed!.y, closeTo(0.225, 1e-6));
    });

    testWidgets('a quick tap (below the long-press threshold) does not '
        'commit', (tester) async {
      var committed = false;
      await tester.pumpWidget(_Harness(onCommit: (_) => committed = true));

      await tester.tapAt(_global(tester, _atFraction(tester, 0.5, 0.5)));
      await tester.pump();

      expect(committed, isFalse);
    });

    testWidgets('dragging outside the canvas bounds before releasing '
        'cancels with no commit', (tester) async {
      var committed = false;
      await tester.pumpWidget(_Harness(onCommit: (_) => committed = true));

      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, 0.5),
        moveTo: const Offset(-40, -40),
      );

      expect(committed, isFalse);
    });

    testWidgets('a second long-press-release overwrites the first commit '
        '(quick correction)', (tester) async {
      final commits = <ZoneCoord>[];
      await tester.pumpWidget(_Harness(onCommit: commits.add));

      await _longPressDragRelease(tester, local: _atFraction(tester, 0.2, 0.2));
      await _longPressDragRelease(tester, local: _atFraction(tester, 0.8, 0.2));

      expect(commits, hasLength(2));
      expect(commits[0].x, isNot(closeTo(commits[1].x, 0.01)));
    });

    testWidgets('with no bounce sink, a release in the dirt band still '
        'commits a low ZoneCoord', (tester) async {
      // An instance given no `onCommitBounce` cannot capture a bounce, so the
      // hinge is disabled and the dirt band is just canvas — the pre-hinge
      // behaviour, kept working rather than assumed gone.
      const geometry = FrontalGeometry();
      ZoneCoord? committed;
      await tester.pumpWidget(_Harness(onCommit: (c) => committed = c));

      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, 0.97),
      );

      expect(committed, isNotNull);
      expect(committed!.y, lessThan(geometry.groundY));
      expect(find.text('IN THE DIRT'), findsNothing);
    });
  });

  // §11.1's dirt-band hinge. The trigger is `y < y_ground` on *release*, in
  // actual mode only, and everything below is about that sentence holding
  // exactly — no wider, no narrower.
  group('Dirt-band hinge (§11.1)', () {
    const geometry = FrontalGeometry();
    const topDown = TopDownGeometry();

    /// A drawing-area fraction that lands inside the dirt band, and one that
    /// lands in the zone. Derived from `y_ground` rather than eyeballed, so
    /// they follow the geometry if the profile changes.
    double fractionForY(double y) =>
        (zoneCanvasExtentMaxY - y) /
        (zoneCanvasExtentMaxY - zoneCanvasExtentMinY);

    testWidgets('a release below y_ground hinges instead of committing', (
      tester,
    ) async {
      var committed = false;
      await tester.pumpWidget(
        _Harness(canCaptureBounce: true, onCommit: (_) => committed = true),
      );

      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, fractionForY(geometry.groundY - 0.1)),
      );

      expect(committed, isFalse, reason: 'the hinge replaces the commit');
      expect(find.text('IN THE DIRT'), findsOneWidget);
      expect(find.text('Back to zone'), findsOneWidget);
      expect(find.text('Depth unknown'), findsOneWidget);
    });

    testWidgets('a release just above y_ground does not hinge', (tester) async {
      // The boundary is the ground line itself, not "low enough to look like
      // dirt" — drawn ground spans it (§11.4).
      ZoneCoord? committed;
      await tester.pumpWidget(
        _Harness(canCaptureBounce: true, onCommit: (c) => committed = c),
      );

      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, fractionForY(geometry.groundY + 0.02)),
      );

      expect(committed, isNotNull);
      expect(committed!.y, greaterThan(geometry.groundY));
      expect(find.text('IN THE DIRT'), findsNothing);
    });

    testWidgets('call mode never hinges — a call is never a bounce (§4.1)', (
      tester,
    ) async {
      ZoneCoord? committed;
      var bounced = false;
      await tester.pumpWidget(
        _Harness(
          mode: ZoneCanvasIntent.call,
          canCaptureBounce: true,
          onCommit: (c) => committed = c,
          onCommitBounce: (_) => bounced = true,
        ),
      );

      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, fractionForY(geometry.groundY - 0.2)),
      );

      expect(bounced, isFalse);
      expect(
        committed,
        isNotNull,
        reason: 'a low call commits a low ZoneCoord',
      );
      expect(committed!.y, lessThan(geometry.groundY));
      expect(find.text('CALL'), findsOneWidget);
    });

    testWidgets('REGRESSION: arming in the dirt and dragging up into the zone '
        'commits a normal actualLocation and never hinges', (tester) async {
      // The arm-low-drag-up-to-correct grammar DIA-005 shipped. The hinge fires
      // on release only, so where the press *started* must not matter at all.
      ZoneCoord? committed;
      var bounced = false;
      await tester.pumpWidget(
        _Harness(
          canCaptureBounce: true,
          onCommit: (c) => committed = c,
          onCommitBounce: (_) => bounced = true,
        ),
      );

      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, 0.97),
        moveTo: _atFraction(tester, 0.5, fractionForY(0.5)),
      );

      expect(bounced, isFalse);
      expect(committed, isNotNull);
      expect(committed!.y, closeTo(0.5, 1e-6));
      expect(find.text('IN THE DIRT'), findsNothing);
    });

    testWidgets('a placement in the top-down plane commits bounceLocation '
        'with shared-x and signed depth', (tester) async {
      final bounces = <BounceCoord>[];
      await tester.pumpWidget(_Harness(onCommitBounce: bounces.add));

      // Hinge in at x = +2 (arm side of the plate, out past the chalk).
      const hingeFx =
          (2.0 - zoneCanvasExtentMinX) /
          (zoneCanvasExtentMaxX - zoneCanvasExtentMinX);
      await _longPressDragRelease(
        tester,
        local: _atFraction(
          tester,
          hingeFx,
          fractionForY(geometry.groundY - 0.2),
        ),
      );
      expect(find.text('IN THE DIRT'), findsOneWidget);

      // Then place the bounce out front, near the top of the depth axis.
      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, hingeFx, 0.1),
      );

      expect(bounces, hasLength(1));
      final bounce = bounces.single;
      expect(bounce.x, closeTo(2, 1e-6), reason: 'lateral axis is shared');
      expect(bounce.depth, closeTo(topDown.depthFeetAtFraction(0.1), 1e-6));
      expect(
        bounce.depth,
        greaterThan(0),
        reason: 'up-screen = toward the pitcher = positive depth (§3.3)',
      );
    });

    testWidgets('a placement behind the seam records negative depth', (
      tester,
    ) async {
      final bounces = <BounceCoord>[];
      await tester.pumpWidget(_Harness(onCommitBounce: bounces.add));

      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, fractionForY(geometry.groundY - 0.2)),
      );
      // Below the seam: a short hop between the plate and the catcher.
      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, 0.95),
      );

      expect(bounces.single.depth, lessThan(0));
      expect(
        bounces.single.depth,
        closeTo(topDown.depthFeetAtFraction(0.95), 1e-6),
      );
    });

    testWidgets('"Depth unknown" records the bounce with the x the hinge '
        'already gave us, and no depth', (tester) async {
      final bounces = <BounceCoord>[];
      await tester.pumpWidget(_Harness(onCommitBounce: bounces.add));

      const hingeFx =
          (-1.5 - zoneCanvasExtentMinX) /
          (zoneCanvasExtentMaxX - zoneCanvasExtentMinX);
      await _longPressDragRelease(
        tester,
        local: _atFraction(
          tester,
          hingeFx,
          fractionForY(geometry.groundY - 0.2),
        ),
      );
      await tester.tap(find.text('Depth unknown'));
      await tester.pump();

      expect(bounces, hasLength(1));
      expect(bounces.single.depth, isNull, reason: 'not captured, not zero');
      expect(bounces.single.x, closeTo(-1.5, 1e-6));
    });

    testWidgets('"Back to zone" un-hinges and commits nothing', (tester) async {
      var committed = false;
      var bounced = false;
      await tester.pumpWidget(
        _Harness(
          onCommit: (_) => committed = true,
          onCommitBounce: (_) => bounced = true,
        ),
      );

      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, fractionForY(geometry.groundY - 0.2)),
      );
      await tester.tap(find.text('Back to zone'));
      await tester.pump();

      expect(bounced, isFalse);
      expect(committed, isFalse);
      expect(find.text('IN THE DIRT'), findsNothing);
      expect(find.text('ACTUAL'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Skip location'), findsOneWidget);
    });

    testWidgets('controls stay outside the drawing area after the hinge too', (
      tester,
    ) async {
      // The reason they moved off-canvas in the first place (§11.4), and the
      // case that made it urgent: after the hinge the dirt is the whole canvas.
      await tester.pumpWidget(const _Harness(canCaptureBounce: true));
      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, fractionForY(geometry.groundY - 0.2)),
      );

      final canvas = _canvasRect(tester);
      for (final label in ['Back to zone', 'Depth unknown']) {
        expect(
          canvas.overlaps(tester.getRect(find.text(label))),
          isFalse,
          reason: '$label overlaps the top-down drawing area',
        );
      }
    });

    testWidgets('opens directly in the top-down plane when given a bounce', (
      tester,
    ) async {
      // How a parent re-enters an already-captured bounce, and how the goldens
      // get there without gestures.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoneCanvas(
              mode: ZoneCanvasIntent.actual,
              value: null,
              bounceValue: BounceCoord(x: 0.5, depth: 1.5),
              onCommit: _noop,
              onCommitBounce: _noop,
              onSkip: _noopVoid,
              onCancel: _noopVoid,
            ),
          ),
        ),
      );

      expect(find.text('IN THE DIRT'), findsOneWidget);
    });
  });

  group('Controls sit outside the drawing area (§11.4)', () {
    testWidgets('Cancel and Skip location do not overlap the canvas', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness());

      final canvas = _canvasRect(tester);
      for (final label in ['Cancel', 'Skip location']) {
        final control = tester.getRect(find.text(label));
        expect(
          canvas.overlaps(control),
          isFalse,
          reason:
              '$label overlaps the drawing area, which is a live hit-target '
              'conflict with the dirt band / hinge trigger',
        );
      }
    });
  });

  group('ZoneCanvas affordances', () {
    testWidgets('Skip location button fires onSkip, not onCommit', (
      tester,
    ) async {
      var skipped = false;
      var committed = false;
      await tester.pumpWidget(
        _Harness(
          onSkip: () => skipped = true,
          onCommit: (_) => committed = true,
        ),
      );

      await tester.tap(find.text('Skip location'));
      await tester.pump();

      expect(skipped, isTrue);
      expect(committed, isFalse);
    });

    testWidgets('Cancel button fires onCancel in call mode', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(
        _Harness(mode: ZoneCanvasIntent.call, onCancel: () => cancelled = true),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('Cancel button fires onCancel in actual mode', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(_Harness(onCancel: () => cancelled = true));

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('underlay content renders', (tester) async {
      await tester.pumpWidget(
        const _Harness(
          underlay: ColoredBox(color: Colors.red, key: Key('underlay')),
        ),
      );

      expect(find.byKey(const Key('underlay')), findsOneWidget);
    });
  });

  group('ZoneCanvas mode labeling', () {
    testWidgets('shows CALL banner in call mode', (tester) async {
      await tester.pumpWidget(const _Harness(mode: ZoneCanvasIntent.call));
      expect(find.text('CALL'), findsOneWidget);
      expect(find.text('ACTUAL'), findsNothing);
    });

    testWidgets('shows ACTUAL banner in actual mode', (tester) async {
      await tester.pumpWidget(const _Harness());
      expect(find.text('ACTUAL'), findsOneWidget);
      expect(find.text('CALL'), findsNothing);
    });
  });
}
