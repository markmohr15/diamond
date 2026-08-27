import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/field_painter.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';

const _canvasSize = Size(700, 640);

/// The field render (§16.3, §18.7), painter-direct: deterministic, no
/// providers. What to look at: the fence curve through 190/200/210 with the
/// foul lines meeting it at the poles; the basepath diamond and circle to
/// scale (60 ft bases, 40 ft rubber); fielder spots as faint numbered rings
/// — stage in ink, and only the play itself (landing, roll, tokens) in
/// accent.
void main() {
  final scheme = deriveScheme(
    accentSeed: StubTeamColors.ownTeam.primary!,
    brightness: Brightness.light,
  );

  Widget canvas({
    FieldCoord? landing,
    FieldCoord? retrieved,
    List<RunnerToken> tokens = const [],
  }) {
    return ColoredBox(
      color: scheme.surface,
      child: CustomPaint(
        size: _canvasSize,
        painter: FieldPainter(
          geometry: FieldGeometry(
            profile: FieldProfile.fastpitch12U,
            size: _canvasSize,
          ),
          ink: scheme.onSurface,
          accent: scheme.primary,
          surface: scheme.surface,
          landing: landing,
          retrieved: retrieved,
          tokens: tokens,
        ),
      ),
    );
  }

  goldenTest(
    'field canvas from the 12U profile',
    fileName: 'field_canvas',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        GoldenTestScenario(
          name: 'ball in play: runners in motion, a third of the way up',
          constraints: BoxConstraints.tight(_canvasSize),
          child: canvas(
            tokens: const [
              RunnerToken(
                runnerId: 'b1',
                label: 'B',
                base: 1,
                origin: 0,
                inMotion: true,
              ),
              RunnerToken(
                runnerId: 'r1',
                label: '1',
                base: 2,
                origin: 1,
                inMotion: true,
              ),
              RunnerToken(runnerId: 'r3', label: '3', base: 3, origin: 3),
            ],
          ),
        ),
        GoldenTestScenario(
          name: 'gap shot rolled to the wall; batter to second, R1 scored',
          constraints: BoxConstraints.tight(_canvasSize),
          child: canvas(
            landing: FieldCoord(x: -70, y: 150),
            retrieved: FieldCoord(x: -95, y: 175),
            tokens: const [
              RunnerToken(runnerId: 'b1', label: 'B', base: 2),
              RunnerToken(runnerId: 'r1', label: '1', base: 4),
            ],
          ),
        ),
      ],
    ),
  );
}
