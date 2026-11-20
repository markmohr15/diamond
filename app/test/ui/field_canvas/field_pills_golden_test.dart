import 'package:alchemist/alchemist.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/field_painter.dart';
import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:flutter/material.dart';

const _canvasSize = Size(700, 640);

/// The SAFE/OUT pills in 14B's states 3–5 (DIA-018d), painter-direct. What
/// to look at: the holder over OUT, which grows to say what it will record;
/// and a pill she was held on until it hid, leaving its partner standing.
/// The hold itself draws nothing (Mark, 2026-11-19), so there is no state
/// to show between the two. Then the tag (DIA-029): the holder over a
/// runner, and a runner over the holder — whichever is under the finger
/// becomes the OUT pill.
void main() {
  final geometry = FieldGeometry(
    profile: FieldProfile.fastpitch12U,
    size: _canvasSize,
  );

  final runnerAt = geometry.runnerTokenCenter(
    base: 2,
    origin: 1,
    inMotion: true,
  );
  final shortstopAt = geometry.toPx(
    standardFielderSpots(FieldProfile.fastpitch12U)[6]!,
  );

  const runnerToSecond = RunnerToken(
    runnerId: 'r1',
    label: '1',
    base: 2,
    origin: 1,
    inMotion: true,
  );

  Widget canvas({
    required Brightness brightness,
    Offset? dragPosition,
    String? dragTokenId,
    int? dragFielderPosition,
    int? holderPosition,
    int? holderDragBase,
    String? outPillDetail,
    Set<(int, BaseCall)> hiddenPills = const {},
    TagTarget? tagTarget,
  }) {
    final scheme = deriveScheme(
      accentSeed: StubTeamColors.ownTeam.primary!,
      brightness: brightness,
    );
    final seam = DiamondSemantics.fromBaseline(
      brightness == Brightness.light ? BrandBaseline.light : BrandBaseline.dark,
    ).clayLine;
    return ColoredBox(
      color: scheme.surface,
      child: CustomPaint(
        size: _canvasSize,
        painter: FieldPainter(
          geometry: geometry,
          ink: scheme.onSurface,
          accent: scheme.primary,
          surface: scheme.surface,
          onAccent: scheme.onPrimary,
          seam: seam,
          tokens: const [runnerToSecond],
          dragPosition: dragPosition,
          dragTokenId: dragTokenId,
          dragFielderPosition: dragFielderPosition,
          holderPosition: holderPosition,
          holderDragBase: holderDragBase,
          outPillDetail: outPillDetail,
          hiddenPills: hiddenPills,
          tagTarget: tagTarget,
        ),
      ),
    );
  }

  List<GoldenTestScenario> scenarios(Brightness brightness) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';
    return [
      GoldenTestScenario(
        name: 'the shortstop with the ball over OUT at second ($suffix)',
        constraints: BoxConstraints.tight(_canvasSize),
        child: canvas(
          brightness: brightness,
          dragPosition: geometry.outAffordanceCenter(2),
          dragFielderPosition: 6,
          holderPosition: 6,
          holderDragBase: 2,
          outPillDetail: 'UNASSISTED · SS',
        ),
      ),
      GoldenTestScenario(
        name: 'the shortstop held on OUT until it hid; SAFE stays ($suffix)',
        constraints: BoxConstraints.tight(_canvasSize),
        child: canvas(
          brightness: brightness,
          dragPosition: geometry.outAffordanceCenter(2),
          dragFielderPosition: 6,
          holderPosition: 6,
          holderDragBase: 2,
          hiddenPills: const {(2, BaseCall.out)},
        ),
      ),
      GoldenTestScenario(
        name: 'the shortstop over the runner: she is the OUT ($suffix)',
        constraints: BoxConstraints.tight(_canvasSize),
        child: canvas(
          brightness: brightness,
          dragPosition: runnerAt,
          dragFielderPosition: 6,
          holderPosition: 6,
          outPillDetail: 'UNASSISTED · SS',
          tagTarget: (center: runnerAt, base: 2, coversRunnerId: 'r1'),
        ),
      ),
      GoldenTestScenario(
        name: 'the runner over the shortstop: she is the OUT ($suffix)',
        constraints: BoxConstraints.tight(_canvasSize),
        child: canvas(
          brightness: brightness,
          dragPosition: shortstopAt,
          dragTokenId: 'r1',
          holderPosition: 6,
          outPillDetail: 'UNASSISTED · SS',
          tagTarget: (center: shortstopAt, base: 2, coversRunnerId: null),
        ),
      ),
    ];
  }

  goldenTest(
    'the pills hide, say what they record, and stand in for a tag',
    fileName: 'field_pills',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        for (final (light, dark) in [
          for (var i = 0; i < 4; i++)
            (scenarios(Brightness.light)[i], scenarios(Brightness.dark)[i]),
        ]) ...[light, dark],
      ],
    ),
  );
}
