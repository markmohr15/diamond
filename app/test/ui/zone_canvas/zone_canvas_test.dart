import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Canvas sized to exactly match the widget's fixed aspect ratio
// ((zoneCanvasExtentMaxX - zoneCanvasExtentMinX) / (zoneCanvasExtentMaxY -
// zoneCanvasExtentMinY) == 3.2 / 2.2), so the rendered canvas fills this
// SizedBox exactly with no letterboxing and the top-left of the SizedBox is
// the coordinate-mapping origin.
const _canvasSize = Size(320, 220);
final _canvasKey = UniqueKey();

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
            key: _canvasKey,
            width: _canvasSize.width,
            height: _canvasSize.height,
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

Offset _global(WidgetTester tester, Offset local) =>
    tester.getTopLeft(find.byKey(_canvasKey)) + local;

/// Long-press at [local] (canvas coordinates), optionally drag to
/// [moveTo], then release — the gesture the widget expects for commit/cancel.
Future<void> _longPressDragRelease(
  WidgetTester tester, {
  required Offset local,
  Offset? moveTo,
}) async {
  final gesture = await tester.startGesture(_global(tester, local));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  if (moveTo != null) {
    await gesture.moveTo(_global(tester, moveTo));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  // Pure conversion-function tests: exact, unambiguous, and independent of
  // where the Cancel/Skip button chrome happens to sit on screen (the
  // gesture-based tests below deliberately avoid those regions).
  group('zoneCoordFromLocal / localFromZoneCoord math', () {
    test('canvas center maps to (0, 0.5)', () {
      const size = _canvasSize;
      final coord = zoneCoordFromLocal(
        Offset(size.width / 2, size.height / 2),
        size,
      );
      expect(coord.x, closeTo(0, 1e-9));
      expect(coord.y, closeTo(0.5, 1e-9));
    });

    test('top-left local origin maps to the min-x/max-y extreme', () {
      final coord = zoneCoordFromLocal(Offset.zero, _canvasSize);
      expect(coord.x, closeTo(zoneCanvasExtentMinX, 1e-9));
      expect(coord.y, closeTo(zoneCanvasExtentMaxY, 1e-9));
    });

    test('bottom-right local corner maps to the max-x/min-y extreme', () {
      final coord = zoneCoordFromLocal(
        Offset(_canvasSize.width, _canvasSize.height),
        _canvasSize,
      );
      expect(coord.x, closeTo(zoneCanvasExtentMaxX, 1e-9));
      expect(coord.y, closeTo(zoneCanvasExtentMinY, 1e-9));
    });

    test('a point above the zone rect is out-of-zone but in-range (y > 1)', () {
      final coord = zoneCoordFromLocal(
        Offset(_canvasSize.width / 2, 30),
        _canvasSize,
      );
      expect(coord.y, greaterThan(zoneMaxY));
      expect(coord.y, lessThanOrEqualTo(zoneCanvasExtentMaxY));
    });

    test('localFromZoneCoord is the inverse of zoneCoordFromLocal', () {
      const local = Offset(77, 133);
      final coord = zoneCoordFromLocal(local, _canvasSize);
      final roundTripped = localFromZoneCoord(coord, _canvasSize);
      expect(roundTripped.dx, closeTo(local.dx, 1e-9));
      expect(roundTripped.dy, closeTo(local.dy, 1e-9));
    });
  });

  group('ZoneCanvas gesture semantics', () {
    // Target points below are chosen inside the canvas's top half, clear of
    // the Cancel/Skip buttons anchored to the bottom-left/bottom-right.
    testWidgets('long-press-release at canvas center commits (0, 0.5)', (
      tester,
    ) async {
      ZoneCoord? committed;
      await tester.pumpWidget(_Harness(onCommit: (c) => committed = c));

      await _longPressDragRelease(
        tester,
        local: Offset(_canvasSize.width / 2, _canvasSize.height / 2),
      );

      expect(committed, isNotNull);
      expect(committed!.x, closeTo(0, 1e-9));
      expect(committed!.y, closeTo(0.5, 1e-9));
    });

    testWidgets('a quick tap (below the long-press threshold) does not '
        'commit', (tester) async {
      var committed = false;
      await tester.pumpWidget(_Harness(onCommit: (_) => committed = true));

      await tester.tapAt(
        _global(
          tester,
          Offset(_canvasSize.width / 2, _canvasSize.height / 2),
        ),
      );
      await tester.pump();

      expect(committed, isFalse);
    });

    testWidgets('dragging outside the canvas bounds before releasing '
        'cancels with no commit', (tester) async {
      var committed = false;
      await tester.pumpWidget(_Harness(onCommit: (_) => committed = true));

      await _longPressDragRelease(
        tester,
        local: Offset(_canvasSize.width / 2, _canvasSize.height / 2),
        moveTo: const Offset(-40, -40),
      );

      expect(committed, isFalse);
    });

    testWidgets('a second long-press-release overwrites the first commit '
        '(quick correction)', (tester) async {
      final commits = <ZoneCoord>[];
      await tester.pumpWidget(_Harness(onCommit: commits.add));

      await _longPressDragRelease(tester, local: const Offset(40, 40));
      await _longPressDragRelease(
        tester,
        local: Offset(_canvasSize.width - 40, 40),
      );

      expect(commits, hasLength(2));
      expect(commits[0].x, isNot(closeTo(commits[1].x, 0.01)));
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
