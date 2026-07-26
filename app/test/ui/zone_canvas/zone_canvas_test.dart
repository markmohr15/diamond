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
  });

  final ZoneCanvasIntent mode;
  final Widget? underlay;
  final ValueChanged<ZoneCoord>? onCommit;
  final VoidCallback? onSkip;
  final VoidCallback? onCancel;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  ZoneCoord? value;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _harnessSize.width,
            height: _harnessSize.height,
            child: ZoneCanvas(
              mode: widget.mode,
              value: value,
              underlay: widget.underlay,
              onCommit: (coord) {
                setState(() => value = coord);
                widget.onCommit?.call(coord);
              },
              onSkip: widget.onSkip ?? () {},
              onCancel: widget.onCancel ?? () {},
            ),
          ),
        ),
      ),
    );
  }
}

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
      final coord = zoneCoordFromLocal(
        Offset(size.width, size.height),
        size,
      );
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

      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, 0.5),
      );

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

    testWidgets('a release in the dirt band still commits a low ZoneCoord — '
        'the hinge is not part of the geometry work', (tester) async {
      const geometry = FrontalGeometry();
      ZoneCoord? committed;
      await tester.pumpWidget(_Harness(onCommit: (c) => committed = c));

      // Just above the canvas bottom: below the ground line, i.e. inside what
      // becomes the hinge trigger region in the bounce-hinge part.
      await _longPressDragRelease(
        tester,
        local: _atFraction(tester, 0.5, 0.97),
      );

      expect(committed, isNotNull);
      expect(committed!.y, lessThan(geometry.groundY));
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

    testWidgets('Cancel button fires onCancel in actual mode', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        _Harness(onCancel: () => cancelled = true),
      );

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
