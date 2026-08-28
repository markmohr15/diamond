import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../call/seeded_code_selector.dart';

const _tabletSize = Size(760, 680);

void _noop() {}

/// The call step as the pitch loop renders it: code + the v0.40 pitch-happened
/// checkmark in the top strip. What to look at: the checkmark sits beside the
/// code inside the fixed-height slot — nothing below it moves — and carries a
/// tap target of its own without touching the drawing area.
///
/// No database behind this: `CallScreen` with a live `onPitchThrown` is all
/// the checkmark needs, so the sheet renders without the loop's bootstrap.
void main() {
  goldenTest(
    'call step with the pitch-happened checkmark',
    fileName: 'loop_call_step_checkmark',
    builder: () {
      final called = ProviderContainer(overrides: [seededCodeSelector]);
      called.read(callDraftProvider.notifier).selectType('dr');
      called.read(callDraftProvider.notifier).selectZone('c1r2');
      addTearDown(called.dispose);

      return GoldenTestGroup(
        columns: 1,
        children: [
          GoldenTestScenario(
            name: 'drop ball called: code, checkmark, zone accented',
            constraints: BoxConstraints.tight(_tabletSize),
            child: UncontrolledProviderScope(
              container: called,
              child: MaterialApp(
                theme: buildTheme(
                  deriveScheme(
                    accentSeed: StubTeamColors.ownTeam.primary!,
                    brightness: Brightness.light,
                  ),
                ),
                home: const Scaffold(body: CallScreen(onPitchThrown: _noop)),
              ),
            ),
          ),
        ],
      );
    },
  );
}
