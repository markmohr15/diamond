import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'seeded_code_selector.dart';

const _tabletSize = Size(760, 680);

Widget _app({
  required ProviderContainer container,
  BatterSide batterSide = BatterSide.R,
  Brightness brightness = Brightness.light,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(
      deriveScheme(
        accentSeed: StubTeamColors.ownTeam.primary!,
        brightness: brightness,
      ),
    ),
    home: Scaffold(body: CallScreen(batterSide: batterSide)),
  ),
);

/// A container already advanced to the state under test. Selecting the type
/// goes through the widget in the tests; here it is set directly so each
/// scenario renders one state without a gesture script.
ProviderContainer _withCall({required String typeId, String? zoneId}) {
  final container = ProviderContainer(overrides: [seededCodeSelector]);
  container.read(callDraftProvider.notifier).selectType(typeId);
  if (zoneId != null) {
    container.read(callDraftProvider.notifier).selectZone(zoneId);
  }
  return container;
}

// Deliberately one column. Alchemist sizes a column to its widest child, and
// the scenario *label* participates in that — so with two columns the first
// label's measured text width sets where the second panel starts. Long labels
// made that a fractional x, which puts every vertical edge in the right-hand
// panel on a half pixel and leaves its anti-aliasing to the rasterizer. It
// matched locally and not on CI. One column gives every scenario the same
// integral origin, so no label can move a pixel.
void main() {
  // Re-enabled in DIA-016f. This was skipped because the image differed
  // between macOS and Linux by anti-aliasing alone — 8 pixels of it — and the
  // comment here said it could be closed once goldens were generated in the
  // same Linux environment CI verifies them in. DIA-016a did exactly that, so
  // the precondition is met and the deferral had outlived itself.
  //
  // What it restores is the picture of **state 1** — the full arsenal before a
  // pitch is chosen — which no other golden covers. `call_screen_variants`
  // has states 2 and 3 in both brightnesses and handednesses.
  goldenTest(
    'call screen, the three states',
    fileName: 'call_screen_states',
    builder: () {
      final empty = ProviderContainer(overrides: [seededCodeSelector]);
      final called = _withCall(typeId: 'dr', zoneId: 'c1r2');
      addTearDown(empty.dispose);
      addTearDown(called.dispose);

      return GoldenTestGroup(
        columns: 1,
        children: [
          GoldenTestScenario(
            name: '1 · no type chosen: the whole arsenal, tappable',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _app(container: empty),
          ),
          GoldenTestScenario(
            name: '3 · drop ball: its five locations, one chosen',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _app(container: called),
          ),
        ],
      );
    },
  );

  goldenTest(
    'call screen, dark and left-handed',
    fileName: 'call_screen_variants',
    builder: () {
      final dark = _withCall(typeId: 'ri', zoneId: 'c2r4');
      final lefty = _withCall(typeId: 'dr', zoneId: 'c1r2');
      addTearDown(dark.dispose);
      addTearDown(lefty.dispose);

      return GoldenTestGroup(
        columns: 1,
        children: [
          // Night games are real (§23.1.4).
          GoldenTestScenario(
            name: 'dark, rise ball: its five locations',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _app(container: dark, brightness: Brightness.dark),
          ),
          // Same zone id as the light scenario above; the highlight moves to
          // the other side because "in" is the batter's side (§10.1).
          GoldenTestScenario(
            name: 'left-handed batter, same call',
            constraints: BoxConstraints.tight(_tabletSize),
            child: _app(container: lefty, batterSide: BatterSide.L),
          ),
        ],
      );
    },
  );
}
