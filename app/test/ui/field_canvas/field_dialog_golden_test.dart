import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:material_ui/material_ui.dart';

const _dialog = Size(620, 360);

/// The field surface's question dialogs (§15.1), in §23.7's language since
/// v0.77: 56 px answer buttons in 14B's grid, the recorded answer solid Ink.
///
/// This golden began because **nothing rendered a `Chip` anywhere in the
/// suite**, and DIA-016d's chip theme shipped with an uncolored label — white
/// on white in a light dialog — which only turned up when Mark ran the
/// simulator. The chips are gone; the reason to look is not.
///
/// What to look at: each label reads against its button, and the selected
/// answer reads against *its* fill, which is a different surface.
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
                  'How was it hit?',
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
