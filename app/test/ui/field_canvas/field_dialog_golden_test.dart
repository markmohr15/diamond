import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';

const _dialog = Size(620, 260);

/// The field surface's question dialogs (§15.1), which are all chips.
///
/// This golden exists because **nothing rendered a `Chip` anywhere in the
/// suite**, and DIA-016d's chip theme shipped with an uncolored label — white
/// on white in a light dialog — which only turned up when Mark ran the
/// simulator. A chip is not a button and does not get its color the same way.
///
/// What to look at: the label reads against the chip, and the selected chip
/// reads against *its* fill, which is a different surface.
Widget _dialogIn(Brightness brightness, {Trajectory? selected}) => MaterialApp(
  theme: buildTheme(
    deriveScheme(
      accentSeed: StubTeamColors.ownTeam.primary!,
      brightness: brightness,
    ),
  ),
  home: Scaffold(
    body: Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(BrandMetrics.space3xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Builder(
                builder: (context) => Text(
                  'How did it come off the bat?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: BrandMetrics.spaceXl),
              TrajectoryRow(selected: selected, onChosen: (_) {}),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  goldenTest(
    'field dialog chips',
    fileName: 'field_dialog_chips',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        GoldenTestScenario(
          name: 'light, nothing chosen',
          constraints: BoxConstraints.tight(_dialog),
          child: _dialogIn(Brightness.light),
        ),
        GoldenTestScenario(
          name: 'dark, line drive selected',
          constraints: BoxConstraints.tight(_dialog),
          child: _dialogIn(Brightness.dark, selected: Trajectory.LINE),
        ),
      ],
    ),
  );
}
