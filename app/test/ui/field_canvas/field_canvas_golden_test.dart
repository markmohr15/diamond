import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/field_painter.dart';
import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
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
  ColorScheme schemeFor(Brightness brightness) => deriveScheme(
    accentSeed: StubTeamColors.ownTeam.primary!,
    brightness: brightness,
  );

  Widget canvas({
    FieldCoord? landing,
    FieldCoord? endedAt,
    List<RunnerToken> tokens = const [],
    int? holderPosition,
    FieldCoord? ballAt,
    Map<int, FieldCoord> movedFielders = const {},
    List<FieldCoord> route = const [],
    Brightness brightness = Brightness.light,
  }) {
    final scheme = schemeFor(brightness);
    final seam = DiamondSemantics.fromBaseline(
      brightness == Brightness.light ? BrandBaseline.light : BrandBaseline.dark,
    ).clayLine;
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
          onAccent: scheme.onPrimary,
          seam: seam,
          landing: landing,
          rollEnd: endedAt,
          tokens: tokens,
          holderPosition: holderPosition,
          ballAt: ballAt,
          movedFielders: movedFielders,
          route: route,
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
          name:
              'bases loaded, ground ball: the forced runner from third is '
              'running home, not done',
          constraints: BoxConstraints.tight(_canvasSize),
          child: canvas(
            landing: FieldCoord(x: -50, y: 95),
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
              RunnerToken(
                runnerId: 'r2',
                label: '2',
                base: 3,
                origin: 2,
                inMotion: true,
              ),
              // The one this scenario exists for: forced home by the
              // walk-up, so she reads like every other runner in motion
              // rather than like a run already in.
              RunnerToken(
                runnerId: 'r3',
                label: '3',
                base: 4,
                origin: 3,
                inMotion: true,
              ),
            ],
          ),
        ),
        GoldenTestScenario(
          name:
              'popup falls in, RF misplays, CF fields, throws SS then 3B: the '
              'roll stops at the RF',
          constraints: BoxConstraints.tight(_canvasSize),
          child: () {
            // Built through the draft, so the roll and route are the ones
            // the surface draws (Mark, 2026-11-13).
            final draft = const PlayDraft(pitchEventId: 'p', batterId: 'b1')
                .copyWith(
                  landing: FieldCoord(x: 36, y: 120),
                  trajectory: Trajectory.POPUP,
                )
                .addingTouch(
                  9,
                  TouchType.BOOTED,
                  location: FieldCoord(x: 40, y: 120),
                )
                .addingTouch(
                  8,
                  TouchType.FIELDED,
                  location: FieldCoord(x: 42, y: 116),
                )
                .addingTouch(
                  6,
                  TouchType.RECEIVED_THROW,
                  location: FieldCoord(x: -22.5, y: 84),
                )
                .addingTouch(
                  5,
                  TouchType.RECEIVED_THROW,
                  location: FieldCoord(x: -36, y: 52),
                );
            return canvas(
              landing: draft.landing,
              endedAt: draft.rollEnd,
              ballAt: draft.ballAt,
              holderPosition: 5,
              route: draft.ballRoute,
              movedFielders: {
                9: FieldCoord(x: 40, y: 120),
                8: FieldCoord(x: 42, y: 116),
              },
              tokens: const [RunnerToken(runnerId: 'b1', label: 'B', base: 2)],
            );
          }(),
        ),
        GoldenTestScenario(
          name: 'gap shot rolled to the wall; batter to second, R1 scored',
          constraints: BoxConstraints.tight(_canvasSize),
          child: canvas(
            landing: FieldCoord(x: -70, y: 150),
            endedAt: FieldCoord(x: -95, y: 175),
            tokens: const [
              RunnerToken(runnerId: 'b1', label: 'B', base: 2),
              RunnerToken(runnerId: 'r1', label: '1', base: 4),
            ],
          ),
        ),
      ],
    ),
  );

  // Who has the ball (§15.1 v0.60). The case this exists for is the last
  // row: on 2026-09-04 a ball lying where a fielder had been dragged read as
  // her holding it, so *the ball is here* and *she has it* have to differ at
  // zero separation.
  final shortstop = FieldCoord(x: -22.5, y: 84);
  final possession = <(String, Widget Function(Brightness))>[
    (
      'between pitches: the catcher holds it by seed',
      (b) => canvas(
        brightness: b,
        holderPosition: 2,
        tokens: const [RunnerToken(runnerId: 'r2', label: '2', base: 2)],
      ),
    ),
    (
      'popup caught by the shortstop: she has it',
      (b) => canvas(
        brightness: b,
        landing: shortstop,
        holderPosition: 6,
        ballAt: shortstop,
      ),
    ),
    (
      'grounder nobody has reached: loose in the open',
      (b) => canvas(
        brightness: b,
        landing: FieldCoord(x: -50, y: 95),
        ballAt: FieldCoord(x: -50, y: 95),
      ),
    ),
    (
      'booted by the shortstop: loose at her feet, not hers',
      (b) => canvas(
        brightness: b,
        landing: FieldCoord(x: -40, y: 66),
        ballAt: shortstop,
        movedFielders: {6: shortstop},
      ),
    ),
  ];

  goldenTest(
    'who has the ball, light and dark',
    fileName: 'field_possession',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        for (final (name, build) in possession)
          for (final b in Brightness.values.reversed)
            GoldenTestScenario(
              name: '$name (${b.name})',
              constraints: BoxConstraints.tight(_canvasSize),
              child: build(b),
            ),
      ],
    ),
  );
}
