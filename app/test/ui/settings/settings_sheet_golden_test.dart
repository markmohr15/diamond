import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/ui/settings/settings_sheet.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _sheet = Size(660, 380);

/// The settings sheet (§23.1.4), opened the way the scorer opens it.
///
/// It is a dialog built from `ChoiceChip`s, and an uncolored chip label has
/// shipped twice in this codebase — white on white, both times found by Mark
/// running the simulator rather than by CI. A new surface made of exactly
/// that widget does not go out unrendered.
///
/// What to look at: the chips and the eyebrow read against the dialog in both
/// themes, and the selected chip reads against *its* fill, which is a
/// different surface from the one behind it.
void main() {
  Widget sheetIn(Brightness brightness) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWith((Ref<AppDatabase> ref) {
        final db = AppDatabase(NativeDatabase.memory());
        ref.onDispose(db.close);
        return db;
      }),
    ],
    child: MaterialApp(
      theme: buildTheme(
        deriveScheme(
          accentSeed: StubTeamColors.ownTeam.primary!,
          brightness: brightness,
        ),
      ),
      home: Scaffold(
        body: Center(
          // The dialog's own chrome, reproduced: a route would hang off the
          // harness's navigator, above this `ProviderScope`, and fail a
          // lookup that succeeds in the app.
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(BrandMetrics.space3xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) => Text(
                      'Settings',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: BrandMetrics.spaceXl),
                  const SettingsBody(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void sheetGolden(Brightness brightness) {
    goldenTest(
      'settings sheet — ${brightness.name}',
      fileName: 'settings_sheet_${brightness.name}',
      builder: () => GoldenTestGroup(
        children: [
          GoldenTestScenario(
            name: 'system selected — nothing chosen yet',
            constraints: BoxConstraints.tight(_sheet),
            child: sheetIn(brightness),
          ),
        ],
      ),
    );
  }

  sheetGolden(Brightness.light);
  sheetGolden(Brightness.dark);
}
