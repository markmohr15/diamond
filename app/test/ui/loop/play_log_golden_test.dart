import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/rules/play_line.dart';
import 'package:diamond/src/ui/loop/play_log_sheet.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const _sheet = Size(660, 520);

/// DIA-024b's log, rendered from lines rather than from a game — the
/// grammar has its own tests, and this golden is about whether a
/// half-inning is *readable at a glance*.
///
/// What to look at: the sentences carry the ink and nothing frames them
/// (§18.7, data-ink first); a play whose error is a second sentence reads
/// as one paragraph rather than two rows, because it is one play; and the
/// inning reads top to bottom, the way a scorebook does, with the viewport
/// parked at the end so the newest play is in view anyway.
///
/// Runs (DIA-010): each run reads quietly under its play, and only *edited*
/// carries the accent, on the sacrifice fly the scorer ruled unearned.
void main() {
  ScoredRun run(
    String runnerId,
    String batterId, {
    required bool earned,
    required bool rbi,
    EarnedRunOverride? earnedOverride,
  }) => ScoredRun(
    eventId: '$runnerId-$batterId',
    anchorId: '$runnerId-$batterId',
    runnerId: runnerId,
    batterId: batterId,
    derivedEarned: earned,
    earnedOverride: earnedOverride,
    derivedRbi: rbi,
    rbiOverride: null,
  );

  // Real output, taken from the §14 fixtures: a play whose error is a
  // second sentence, a wild pitch moving three runners, both sacrifices,
  // and an award.
  const d3k =
      'b1 struck out, reached first on a wild pitch. '
      'On a throwing error by the C, b1 advanced to second '
      'and r1 advanced to third.';
  const wp = 'Wild pitch, r3 scored, r2 scored, r1 advanced to second.';
  const sac = 'b1 out on a sacrifice fly to CF, r3 scored.';
  const boot =
      'b1 singled to left. On a fielding error by the LF, '
      'b1 advanced to second.';
  const ci = "b1 reached on catcher's interference, r1 advanced to second.";
  final runs = {
    wp: [
      run('r3', 'b2', earned: true, rbi: false),
      run('r2', 'b2', earned: false, rbi: false),
    ],
    sac: [
      run(
        'r3',
        'b1',
        earned: true,
        rbi: true,
        earnedOverride: EarnedRunOverride(runEventId: 'r3-b1', earned: false),
      ),
    ],
  };
  final lines = [
    for (final text in const [d3k, wp, sac, boot, ci])
      PlayLine(
        pitchEventId: text,
        sentences: [text],
        runs: runs[text] ?? const [],
      ),
  ];

  Widget log(Brightness brightness) => ProviderScope(
    overrides: [playLogProvider.overrideWith((ref) async => lines)],
    child: MaterialApp(
      theme: buildTheme(
        deriveScheme(
          accentSeed: StubTeamColors.ownTeam.primary!,
          brightness: brightness,
        ),
      ),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(BrandMetrics.space3xl),
            child: PlayLogBody(),
          ),
        ),
      ),
    ),
  );

  goldenTest(
    'play log',
    fileName: 'play_log',
    builder: () => GoldenTestGroup(
      children: [
        GoldenTestScenario(
          name: 'a half-inning, in the order it happened',
          constraints: BoxConstraints.tight(_sheet),
          child: log(Brightness.light),
        ),
        GoldenTestScenario(
          name: 'dark',
          constraints: BoxConstraints.tight(_sheet),
          child: log(Brightness.dark),
        ),
      ],
    ),
  );
}
