import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
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
  BounceCoord? bounceValue,
  Widget? underlay,
  BatterSide batterSide = BatterSide.R,
  CanvasFidelity fidelity = CanvasFidelity.restrained,
  bool showBatterSilhouette = false,
}) {
  return ZoneCanvas(
    mode: mode,
    value: value,
    batterSide: batterSide,
    showBatterSilhouette: showBatterSilhouette,
    fidelity: fidelity,
    // Passing a bounce opens the canvas on the top-down plane, which is how
    // these reach it without driving the hinge gesture.
    bounceValue: bounceValue,
    underlay: underlay,
    onCommit: (_) {},
    onCommitBounce: (_) {},
    onSkip: () {},
    onCancel: () {},
  );
}

// The app's own theme, not Material's defaults: since DIA-012 the canvas reads
// its accent, atmosphere, and zone fill from the scheme, so a golden rendered
// under ThemeData.light() would be a picture of a theme the app never shows.
// Own-team context, which is the default everywhere after onboarding (§23.3).
Widget _themedApp(Widget child, Brightness brightness) => MaterialApp(
  theme: buildTheme(
    deriveScheme(
      accentSeed: StubTeamColors.ownTeam.primary!,
      brightness: brightness,
    ),
  ),
  home: Material(child: child),
);

Widget _lightApp(Widget child) => _themedApp(child, Brightness.light);

Widget _darkApp(Widget child) => _themedApp(child, Brightness.dark);

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
          // The silhouette is off on the entry canvas while its drawing is
          // provisional (DIA-013). Kept switched on here, in one scenario, so
          // the path stays covered and the figure can still be looked at
          // without running the app.
          GoldenTestScenario(
            name: 'call, silhouette on, left-handed batter',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _canvas(
              mode: ZoneCanvasIntent.call,
              batterSide: BatterSide.L,
              showBatterSilhouette: true,
            ),
          ),
          GoldenTestScenario(
            name: 'actual, marker + underlay',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              value: ZoneCoord(x: 0.3, y: 0.6),
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

  // The top-down plane (§3.3), after §11.1's hinge. Deliberately unmistakable
  // against the frontal goldens above: no zone rect, no call grid, dirt edge to
  // edge, a true-pentagon plate and a depth ruler. What must match across the
  // two sets is the plate's width — the planes share the lateral axis exactly.
  goldenTest(
    'ZoneCanvas top-down plane',
    fileName: 'zone_canvas_top_down',
    builder: () => _lightApp(
      GoldenTestGroup(
        columns: 2,
        children: [
          GoldenTestScenario(
            name: 'tablet, bounce out front',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              bounceValue: BounceCoord(x: 0.6, depth: 1.4),
            ),
          ),
          GoldenTestScenario(
            name: 'tablet, short hop behind the seam',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              bounceValue: BounceCoord(x: -1.2, depth: -0.8),
            ),
          ),
          GoldenTestScenario(
            name: 'phone, bounce out front',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              bounceValue: BounceCoord(x: -0.4, depth: 2.1),
            ),
          ),
          // Depth was never captured, so there is no point to place: the band
          // spans every depth at the lateral position we do know (§11.1).
          GoldenTestScenario(
            name: 'phone, in the dirt, depth unknown',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              bounceValue: BounceCoord(x: 1.8),
            ),
          ),
        ],
      ),
    ),
  );

  // §11.4 makes fidelity a question settled by field test in daylight, not by
  // argument, so both treatments exist behind the *same* coordinate mapping and
  // these sheets are what gets compared. Geometry is identical in both; only
  // paint differs. One of the two is deleted once a choice is made.
  goldenTest(
    'ZoneCanvas rich fidelity',
    fileName: 'zone_canvas_rich',
    builder: () => _lightApp(
      GoldenTestGroup(
        columns: 2,
        children: [
          GoldenTestScenario(
            name: 'frontal, tablet, rich',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              value: ZoneCoord(x: 0.3, y: 0.6),
              fidelity: CanvasFidelity.rich,
            ),
          ),
          GoldenTestScenario(
            name: 'top-down, tablet, rich',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              bounceValue: BounceCoord(x: 0.6, depth: 1.4),
              fidelity: CanvasFidelity.rich,
            ),
          ),
          GoldenTestScenario(
            name: 'frontal, phone, rich',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(
              mode: ZoneCanvasIntent.call,
              fidelity: CanvasFidelity.rich,
            ),
          ),
          GoldenTestScenario(
            name: 'top-down, phone, rich',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              bounceValue: BounceCoord(x: -0.4, depth: 2.1),
              fidelity: CanvasFidelity.rich,
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
        columns: 2,
        children: [
          GoldenTestScenario(
            name: 'actual, marker, dark theme',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              value: ZoneCoord(x: 0.1, y: 0.7),
            ),
          ),
          GoldenTestScenario(
            name: 'frontal, dark theme, rich',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              value: ZoneCoord(x: 0.1, y: 0.7),
              fidelity: CanvasFidelity.rich,
            ),
          ),
          GoldenTestScenario(
            name: 'top-down, dark theme',
            constraints: BoxConstraints.tight(_phoneSize),
            child: _canvas(
              mode: ZoneCanvasIntent.actual,
              bounceValue: BounceCoord(x: 0.1, depth: 0.9),
            ),
          ),
        ],
      ),
    ),
  );
}
