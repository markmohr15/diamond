import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/rules/play_line.dart';
import 'package:diamond/src/ui/loop/play_log_sheet.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _sheet = Size(660, 360);

/// DIA-024b's log, rendered from lines rather than from a game — the
/// grammar has its own tests, and this golden is about whether a
/// half-inning is *readable at a glance*.
///
/// What to look at: the sentences carry the ink and nothing frames them
/// (§18.7, data-ink first); a play whose error is a second sentence reads
/// as one paragraph rather than two rows, because it is one play; and the
/// newest is at the top, which is where the eye lands.
void main() {
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
  final lines = [
    for (final text in const [d3k, wp, sac, boot, ci])
      PlayLine(pitchEventId: text, sentences: [text]),
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
          name: 'a half-inning, newest first',
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
