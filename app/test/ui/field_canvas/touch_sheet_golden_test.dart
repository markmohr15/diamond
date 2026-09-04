import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/ui/field_canvas/play_chain_strip.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _sheet = Size(680, 470);

/// §15.3's menu on a touch node, opened the way the scorer opens it.
///
/// This golden exists because nothing in the suite rendered this sheet, and
/// it shipped with an unreadable `Remove` — `ListTileThemeData.titleTextStyle`
/// took a `BrandType` style, which carries no color, and the title fell
/// through to the ambient `DefaultTextStyle`. White on near-white. That is
/// the same defect `field_dialog_chips` was written for one slot earlier,
/// and both reached Mark through the simulator rather than through CI.
///
/// It taps the real node rather than rebuilding the sheet's contents here,
/// so the golden cannot drift away from the widget that had the bug.
///
/// What to look at: every line of the sheet reads against the dialog — the
/// misplay chips and `Remove` with its icon. The `Ordinary effort?` row that
/// sat between them is gone as of v0.56: the judgment is no longer a flag on
/// the touch, it is which advance the scorer links to it (§13.2).
void main() {
  final draft = const PlayDraft(pitchEventId: 'p', batterId: 'b')
      .copyWith(
        landing: FieldCoord(x: -50, y: 95),
        trajectory: Trajectory.GROUND,
      )
      .addingTouch(6, TouchType.BOOTED);
  final node = chainNodeKey(draft.entries.whereType<TouchEntry>().first.key);

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
          child: PlayChainStrip(draft: draft, runnerLabels: const {'b': 'B'}),
        ),
      ),
    ),
  );

  // A dialog route paints over the whole test surface rather than its
  // scenario box, so the two brightnesses cannot share one image the way
  // `field_dialog_chips` does — one scenario per file is the only honest
  // way to tap the real node.
  void sheetGolden(String name, Brightness brightness) {
    goldenTest(
      'touch node sheet — ${brightness.name}',
      fileName: 'touch_sheet_${brightness.name}',
      pumpBeforeTest: (tester) async {
        await tester.tap(find.byKey(node));
        await tester.pumpAndSettle();
      },
      builder: () => GoldenTestGroup(
        children: [
          GoldenTestScenario(
            name: name,
            constraints: BoxConstraints.tight(_sheet),
            child: sheetIn(brightness),
          ),
        ],
      ),
    );
  }

  sheetGolden('booted node — retype or remove', Brightness.light);
  sheetGolden('booted node — retype or remove', Brightness.dark);
}
