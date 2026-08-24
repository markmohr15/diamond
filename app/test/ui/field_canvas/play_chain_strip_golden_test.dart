import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/ui/field_canvas/play_chain_strip.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _stripSize = Size(700, 130);

/// §15.2's strip as the fixtures render it. What to look at: misplay nodes
/// (booted, wild throw) carry the semantic amber — fault not yet
/// adjudicated — while the short-hop receiving node gets only an underline
/// (information, not fault); runner consequences hang beneath the entry
/// that caused them, unattributed movement beneath ⚾; the trailing + is
/// the ⚖ insertion point.
void main() {
  final base = const PlayDraft(
    pitchEventId: 'p',
    batterId: 'b',
  ).copyWith(landing: FieldCoord(x: -50, y: 95), trajectory: Trajectory.GROUND);

  Widget strip(PlayDraft draft) {
    return ProviderScope(
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
              'play 02: boot (amber) → advance, wild throw (amber) → '
              'advance',
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
              'scored under ⚾, tag out under its touch',
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
