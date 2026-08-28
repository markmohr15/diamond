import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/ui/loop/outcome_step.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';

const _sheet = Size(620, 780);

/// §11.1's outcome sheet, rebuilt on panel 5A (DIA-014a).
///
/// What to look at: **five primaries of equal prominence in frequency order**,
/// then everything else as a wrapped chip row. Nothing is promoted by the
/// pitch's location — the sheet looks identical whatever was captured, which
/// is what makes the five positions learnable.
///
/// The D3K variant is the same sheet plus one conditional primary: it is an
/// outcome that opens a surface, like In play, not a note on a strikeout.
Widget _sheetIn(Brightness brightness, {bool droppedThirdStrike = false}) =>
    MaterialApp(
      theme: buildTheme(
        deriveScheme(
          accentSeed: StubTeamColors.ownTeam.primary!,
          brightness: brightness,
        ),
      ),
      home: Scaffold(
        body: Center(
          child: OutcomeStep(
            onChosen: (_, __, ___) {},
            onDroppedThirdStrike: droppedThirdStrike ? () {} : null,
          ),
        ),
      ),
    );

void main() {
  goldenTest(
    'outcome sheet, five primaries and the rest',
    fileName: 'outcome_sheet',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        GoldenTestScenario(
          name: 'light',
          constraints: BoxConstraints.tight(_sheet),
          child: _sheetIn(Brightness.light),
        ),
        GoldenTestScenario(
          name: 'dark, two strikes and she may run',
          constraints: BoxConstraints.tight(_sheet),
          child: _sheetIn(Brightness.dark, droppedThirdStrike: true),
        ),
      ],
    ),
  );
}
