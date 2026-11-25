import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/ui/field_canvas/play_chain_strip.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const _stripSize = Size(900, 220);

/// §15.2's strip as the fixtures render it (v0.77, board 16A). What to look
/// at: every step is a button that says what happened — *SS booted*, *SS
/// threw wild* filled with Rosin (fault not yet adjudicated), the short-hop
/// reception only underlined (information, not fault); runners read in
/// words beneath the step that moved them, unattributed movement beneath
/// the ball; no "+" chips anywhere, and no ⚾ or ⌂ glyphs.
void main() {
  final base = const PlayDraft(
    pitchEventId: 'p',
    batterId: 'b',
  ).copyWith(landing: FieldCoord(x: -50, y: 95), trajectory: Trajectory.GROUND);

  Widget strip(PlayDraft draft) {
    // The ⚾ node reads the game to decide whether it is live (DIA-019 H2),
    // so the strip needs a database the way the touch sheet already did.
    return ProviderScope(
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
            brightness: Brightness.light,
          ),
        ),
        home: Scaffold(
          body: Center(
            child: PlayChainStrip(
              draft: draft,
              runnerLabels: const {'b': 'B', 'r3': '3'},
            ),
          ),
        ),
      ),
    );
  }

  goldenTest(
    'play chain strip states',
    fileName: 'play_chain_strip',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name:
              'play 02: boot (Rosin) then the batter safe at 1st; wild throw '
              '(Rosin) then the batter to 3rd',
          constraints: BoxConstraints.tight(_stripSize),
          child: strip(
            base
                .addingTouch(6, TouchType.BOOTED)
                .addingLeg('b', from: 0, to: 1)
                .addingTouch(6, TouchType.WILD_THROW)
                .addingLeg('b', from: 1, to: 3),
          ),
        ),
        GoldenTestScenario(
          name:
              'play 03 shape: clean touches, short-hop underline, R3 '
              'scored under the ball, the batter out under her tag',
          constraints: BoxConstraints.tight(_stripSize),
          child: strip(
            base
                .addingTouch(9, TouchType.FIELDED)
                .addingLeg('r3', from: 3, to: 4)
                .addingLeg('b', from: 0, to: 1)
                .addingTouch(6, TouchType.RECEIVED_THROW)
                .updatingEntry(
                  3,
                  (e) => (e as TouchEntry).copyWith(
                    receivedQuality: ReceivedQuality.SHORT_HOP,
                  ),
                )
                .addingTouch(6, TouchType.TAG_APPLIED)
                .addingOut('b', atBase: 2, how: How.TAG, putoutKey: 4),
          ),
        ),
      ],
    ),
  );
}
