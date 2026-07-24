import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/material.dart';

// Container sizes chosen to exercise both branches of ZoneCanvas's
// aspect-ratio-fit layout: the tablet box is wider than the canvas's own
// aspect ratio (height-limited, letterboxed left/right); the phone box is
// narrower (width-limited, letterboxed top/bottom).
const _tabletSize = Size(800, 400);
const _phoneSize = Size(320, 500);

Widget _canvas({
  required ZoneCanvasIntent mode,
  ZoneCoord? value,
  Widget? underlay,
  BallKind ballKind = BallKind.baseball,
}) {
  return ZoneCanvas(
    mode: mode,
    value: value,
    underlay: underlay,
    ballKind: ballKind,
    onCommit: (_) {},
    onSkip: () {},
    onCancel: () {},
  );
}

Widget _lightApp(Widget child) =>
    MaterialApp(theme: ThemeData.light(), home: Material(child: child));

Widget _darkApp(Widget child) => MaterialApp(
  theme: ThemeData.dark(),
  home: Material(child: child),
);

void main() {
  goldenTest(
    'ZoneCanvas on a tablet-width container',
    fileName: 'zone_canvas_tablet',
    builder: () => _lightApp(
      GoldenTestGroup(
        columns: 2,
        children: [
          GoldenTestScenario(
            name: 'call, empty',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _canvas(mode: ZoneCanvasIntent.call),
          ),
          GoldenTestScenario(
            name: 'actual, marker + underlay, softball',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              value: ZoneCoord(x: 0.3, y: 0.6),
              ballKind: BallKind.softball,
              underlay: const ColoredBox(color: Color(0x334CAF50)),
            ),
          ),
        ],
      ),
    ),
  );

  goldenTest(
    'ZoneCanvas on a phone-width container',
    fileName: 'zone_canvas_phone',
    builder: () => _lightApp(
      GoldenTestGroup(
        columns: 2,
        children: [
          GoldenTestScenario(
            name: 'actual, empty',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(mode: ZoneCanvasIntent.actual),
          ),
          GoldenTestScenario(
            name: 'call, marker',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(
              mode: ZoneCanvasIntent.call,
              value: ZoneCoord(x: -0.5, y: 0.2),
            ),
          ),
        ],
      ),
    ),
  );

  goldenTest(
    'ZoneCanvas in dark mode',
    fileName: 'zone_canvas_dark',
    builder: () => _darkApp(
      GoldenTestGroup(
        columns: 1,
        children: [
          GoldenTestScenario(
            name: 'actual, marker, dark theme',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              value: ZoneCoord(x: 0.1, y: 0.7),
            ),
          ),
        ],
      ),
    ),
  );
}
