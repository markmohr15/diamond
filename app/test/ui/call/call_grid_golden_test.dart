import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/call/call_zone.dart';
import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/material.dart';

const _tabletSize = Size(700, 620);

/// The canvas in calling mode. Bypasses `CallScreen` so the grid itself is what
/// the golden shows, with no type row or code display competing for the frame.
Widget _grid({
  required CallZoneLayout layout,
  Set<String>? callableZoneIds,
  String? selectedZoneId,
  BatterSide batterSide = BatterSide.R,
}) => ZoneCanvas(
  mode: ZoneCanvasIntent.call,
  value: null,
  batterSide: batterSide,
  callLayout: layout,
  callableZoneIds: callableZoneIds,
  selectedZoneId: selectedZoneId,
  onZoneSelected: (_) {},
  onCommit: (_) {},
  onSkip: () {},
  onCancel: () {},
);

Widget _app(Widget child) => MaterialApp(
  theme: buildTheme(
    deriveScheme(
      accentSeed: StubTeamColors.ownTeam.primary!,
      brightness: Brightness.light,
    ),
  ),
  home: Material(child: child),
);

void main() {
  // Both ends of §10.1's ladder on one sheet: the same 25 canonical cells, one
  // layout grouping the ring into four chase zones and one leaving all 25
  // separate. What must read identically across them is the geometry — only
  // the outlines move, because only the grouping differs.
  goldenTest(
    'call grid, coarse and fine layouts',
    fileName: 'call_grid_layouts',
    builder: () => _app(
      GoldenTestGroup(
        columns: 2,
        children: [
          GoldenTestScenario(
            name: 'coarse (13 zones), nothing selected',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _grid(layout: StubTeamCallConfig.coarseLayout()),
          ),
          GoldenTestScenario(
            name: 'fine (25 zones), nothing selected',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _grid(layout: StubTeamCallConfig.fineLayout()),
          ),
        ],
      ),
    ),
  );

  goldenTest(
    'call grid, selection and narrowing',
    fileName: 'call_grid_states',
    builder: () {
      final config = StubTeamCallConfig.narrowedConfig();
      final inZoneOnly = config.callableZonesByType['ch']!;
      return _app(
        GoldenTestGroup(
          columns: 2,
          children: [
            // The accent goes to the datum (§23.1.3): the selected zone, not
            // the frame around it.
            GoldenTestScenario(
              name: 'selected: low and inside',
              constraints: BoxConstraints.tight(_tabletSize),
              child: _grid(layout: config.layout, selectedZoneId: 'c1r1'),
            ),
            // Narrowed type: the chase zones go quiet. Geometry is unchanged
            // from the scenario beside it, which is the point (§10.3).
            GoldenTestScenario(
              name: 'narrowed type: chases quiet',
              constraints: BoxConstraints.tight(_tabletSize),
              child: _grid(
                layout: config.layout,
                callableZoneIds: inZoneOnly,
                selectedZoneId: 'c2r2',
              ),
            ),
          ],
        ),
      );
    },
  );

  // Handedness moves the *label*, never the geometry (§11.4's never-mirror
  // rule). The two scenarios below select the zone a coach would call "in" for
  // that batter, and the highlight lands on opposite sides of an otherwise
  // identical grid.
  goldenTest(
    "call grid, inside is the batter's side",
    fileName: 'call_grid_handedness',
    builder: () => _app(
      GoldenTestGroup(
        columns: 2,
        children: [
          GoldenTestScenario(
            name: 'right-handed batter, inside selected',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _grid(
              layout: StubTeamCallConfig.coarseLayout(),
              selectedZoneId: 'c1r2',
            ),
          ),
          GoldenTestScenario(
            name: 'left-handed batter, inside selected',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _grid(
              layout: StubTeamCallConfig.coarseLayout(),
              selectedZoneId: 'c1r2',
              batterSide: BatterSide.L,
            ),
          ),
        ],
      ),
    ),
  );
}
