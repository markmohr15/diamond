import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/ui/loop/pitch_chrome.dart';
import 'package:diamond/src/ui/loop/pitch_flow.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:diamond/src/ui/theme/theme_mode_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const _size = Size(900, 124);

/// 15A's batter strip and rail (DIA-021c), painter-free and store-free. What
/// to look at: the stop you are on carries the accent and nothing else does;
/// a stop you can jump to is outlined in ink; a stop behind you is filled
/// with ink and echoes what it recorded. FIELD is only there between
/// pitches. BATS and LIGHT / DARK fill the chosen segment with ink, never
/// with the accent.
void main() {
  // Pitch 4 of the plate appearance, runners on first and third: a filled
  // base beside an empty one is where the bases used to run together.
  const game = GameState(
    pitchesThisPlateAppearance: 3,
    bases: BaseState(first: 'r1', third: 'r3'),
    currentBatterId: 'b1',
  );

  Widget chrome(
    Brightness brightness,
    PitchFlowState flow, {
    bool field = false,
  }) {
    return ProviderScope(
      overrides: [
        gameControllerProvider.overrideWith(() => _FixedGame(game)),
        pitchFlowProvider.overrideWith(() => _FixedFlow(flow)),
        batterSideProvider.overrideWithValue(BatterSide.R),
        themeModeProvider.overrideWith(
          () => _FixedTheme(
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(
          deriveScheme(
            accentSeed: StubTeamColors.ownTeam.primary!,
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: Column(
            children: [
              BatterStrip(showBats: true, onField: field ? () {} : null),
              const PitchRail(),
            ],
          ),
        ),
      ),
    );
  }

  const calling = PitchFlowState();
  const jumped = PitchFlowState(step: PitchStep.actual);
  final result = PitchFlowState(
    step: PitchStep.outcome,
    intent: const CallIntent(pitchTypeId: 'dr', zoneId: 'c2r1', code: '702'),
    actual: ZoneCoord(x: 0.7, y: 0.2),
  );

  List<GoldenTestScenario> scenarios(Brightness b) {
    final suffix = b == Brightness.light ? 'light' : 'dark';
    return [
      GoldenTestScenario(
        name: 'calling: 1 is current, 2 is live ($suffix)',
        constraints: BoxConstraints.tight(_size),
        child: chrome(b, calling, field: true),
      ),
      GoldenTestScenario(
        name: 'jumped past the call: no call, locating ($suffix)',
        constraints: BoxConstraints.tight(_size),
        child: chrome(b, jumped),
      ),
      GoldenTestScenario(
        name: 'the result: both stops done, each says what it took ($suffix)',
        constraints: BoxConstraints.tight(_size),
        child: chrome(b, result),
      ),
    ];
  }

  goldenTest(
    'the batter strip and the rail',
    fileName: 'pitch_chrome',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        for (var i = 0; i < 3; i++) ...[
          scenarios(Brightness.light)[i],
          scenarios(Brightness.dark)[i],
        ],
      ],
    ),
  );
}

class _FixedGame extends GameController {
  _FixedGame(this._state);
  final GameState _state;

  @override
  Future<GameState> build() async => _state;
}

class _FixedFlow extends PitchFlowController {
  _FixedFlow(this._state);
  final PitchFlowState _state;

  @override
  PitchFlowState build() => _state;
}

class _FixedTheme extends ThemeModeController {
  _FixedTheme(this._mode);
  final ThemeMode _mode;

  @override
  Future<ThemeMode> build() async => _mode;
}
