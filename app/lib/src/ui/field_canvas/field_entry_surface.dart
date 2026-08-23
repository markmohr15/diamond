import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/field_painter.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
const Key fieldCommitKey = Key('fieldCommit');
@visibleForTesting
const Key fieldDiscardKey = Key('fieldDiscard');
@visibleForTesting
const Key offWallChipKey = Key('offWallChip');
@visibleForTesting
const Key fieldDistanceKey = Key('fieldDistance');
@visibleForTesting
const Key fieldCanvasKey = Key('fieldCanvas');

/// How close (px) a runner release must be to a base to snap onto it.
/// Tuned literal: generous enough for a gloved thumb on a sideline tablet.
const double _snapRadiusPx = 36;

/// How near the fence (ft, either side) a landing suggests `offWall`
/// (§15.1). Tuned literal — the spline is exact, thumbs aren't.
const double _offWallToleranceFt = 6;

/// The DIA-008a field surface (§15.1 subset): landing tap/drag with live
/// distance, trajectory row, runner drags to bases, and the atomic ✓
/// (§15.5). Fielder touches, throws, the chain strip, and its chips are
/// DIA-008b; this surface is built to grow them, not be replaced by them.
///
/// Reads the *pre-play* base state from the fold — the draft's runner moves
/// exist only here and in the journal until commit.
class FieldEntrySurface extends ConsumerStatefulWidget {
  const FieldEntrySurface({required this.draft, super.key});

  final PlayDraft draft;

  @override
  ConsumerState<FieldEntrySurface> createState() => _FieldEntrySurfaceState();
}

/// One in-flight gesture: a landing entry or a runner drag, decided at
/// pointer-down by what the finger landed on.
class _ActiveDrag {
  _ActiveDrag({required this.start, this.runnerId}) : current = start;

  final Offset start;
  Offset current;

  /// Null for a landing gesture.
  final String? runnerId;
}

class _FieldEntrySurfaceState extends ConsumerState<FieldEntrySurface> {
  _ActiveDrag? _drag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draft = widget.draft;
    final controller = ref.read(playDraftProvider.notifier);
    final bases = ref.watch(
      gameControllerProvider.select(
        (state) => state.valueOrNull?.bases ?? BaseState.empty,
      ),
    );
    final tokens = _tokens(draft, bases);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                _distanceLabel(draft),
                key: fieldDistanceKey,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                key: fieldDiscardKey,
                onPressed: controller.discard,
                icon: const Icon(Icons.close),
                tooltip: 'Discard play',
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: fieldCommitKey,
                onPressed: draft.committable ? controller.commit : null,
                icon: const Icon(Icons.check),
                label: const Text('Commit play'),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final geometry = FieldGeometry(
                profile: FieldProfile.fastpitch12U,
                size: constraints.biggest,
              );
              return GestureDetector(
                onPanDown: (details) =>
                    _onDown(details.localPosition, geometry, tokens),
                onPanUpdate: (details) => setState(() {
                  _drag?.current = details.localPosition;
                }),
                onPanEnd: (_) => _onUp(geometry, controller),
                onPanCancel: () => setState(() => _drag = null),
                child: CustomPaint(
                  key: fieldCanvasKey,
                  size: constraints.biggest,
                  painter: FieldPainter(
                    geometry: geometry,
                    ink: scheme.onSurface,
                    accent: scheme.primary,
                    surface: scheme.surface,
                    landing: draft.landing,
                    retrieved: draft.retrieved,
                    tokens: tokens,
                    dragPosition: _drag?.current,
                    dragTokenId: _drag?.runnerId,
                  ),
                ),
              );
            },
          ),
        ),
        if (draft.landing != null && _nearFence(draft.landing!))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilterChip(
              key: offWallChipKey,
              label: const Text('Off the wall'),
              selected: draft.offWall,
              onSelected: (value) => controller.setOffWall(offWall: value),
            ),
          ),
        if (draft.landing != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TrajectoryRow(
              selected: draft.trajectory,
              onChosen: controller.setTrajectory,
            ),
          ),
      ],
    );
  }

  /// Everyone the canvas shows as draggable: the batter-runner, then the
  /// fold's base runners — each at their draft position when a move exists.
  List<RunnerToken> _tokens(PlayDraft draft, BaseState bases) {
    int shownBase(String runnerId, int origin) {
      for (final move in draft.runnerMoves) {
        if (move.runnerId == runnerId) return move.to;
      }
      return origin;
    }

    return [
      RunnerToken(
        runnerId: draft.batterId,
        label: 'B',
        base: shownBase(draft.batterId, 0),
      ),
      for (final (origin, runnerId) in [
        (1, bases.first),
        (2, bases.second),
        (3, bases.third),
      ])
        if (runnerId != null)
          RunnerToken(
            runnerId: runnerId,
            label: '$origin',
            base: shownBase(runnerId, origin),
          ),
    ];
  }

  void _onDown(
    Offset position,
    FieldGeometry geometry,
    List<RunnerToken> tokens,
  ) {
    // A finger on a token starts a runner drag; anywhere else, a landing
    // gesture. Painter and hit test share the geometry's tokenCenter, so
    // what you grab is what you saw.
    for (final token in tokens) {
      final center = geometry.tokenCenter(token.base);
      if ((position - center).distance <= _snapRadiusPx) {
        setState(() {
          _drag = _ActiveDrag(start: position, runnerId: token.runnerId);
        });
        return;
      }
    }
    setState(() => _drag = _ActiveDrag(start: position));
  }

  /// The base the play found this runner on — moves record net advance from
  /// here (see [RunnerMove]), never from a mid-play draft position.
  int _originBase(RunnerToken token) {
    if (token.runnerId == widget.draft.batterId) return 0;
    for (final move in widget.draft.runnerMoves) {
      if (move.runnerId == token.runnerId) return move.from;
    }
    return token.base;
  }

  void _onUp(FieldGeometry geometry, PlayDraftController controller) {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);

    if (drag.runnerId == null) {
      // Landing gesture, both grips (§15.1): landing at touch-down; a real
      // drag also records where the roll ended.
      final landing = geometry.toField(drag.start);
      final moved = (drag.current - drag.start).distance > kTouchSlop;
      controller.setLanding(
        landing,
        retrieved: moved ? geometry.toField(drag.current) : null,
      );
      return;
    }

    // Runner drag: snap to the nearest base affordance, or spring back.
    // The release carries its forced cascade (runners never pass each
    // other): the display bases and origins of everyone on the canvas feed
    // [cascadeRunnerMove], and the batch lands as one draft mutation.
    for (final base in const [1, 2, 3, 4]) {
      final center = base == 4 ? geometry.plate : geometry.baseCenter(base);
      if ((drag.current - center).distance <= _snapRadiusPx) {
        final bases =
            ref.read(gameControllerProvider).valueOrNull?.bases ??
            BaseState.empty;
        final slots = [
          for (final token in _tokens(widget.draft, bases))
            (
              runnerId: token.runnerId,
              origin: _originBase(token),
              base: token.base,
            ),
        ];
        controller.moveRunners(
          cascadeRunnerMove(slots, movedId: drag.runnerId!, to: base),
        );
        return;
      }
    }
  }

  bool _nearFence(FieldCoord landing) {
    final geometry = FieldGeometry(
      profile: FieldProfile.fastpitch12U,
      size: const Size(100, 100),
    );
    return geometry.fenceDepthFt(landing).abs() <= _offWallToleranceFt;
  }

  String _distanceLabel(PlayDraft draft) {
    final drag = _drag;
    final landing = draft.landing;

    // Mid-gesture: live number under the finger (§16.3) — the landing about
    // to be, or the roll in progress.
    if (drag != null && drag.runnerId == null) {
      final geometry = _labelGeometry();
      final at = FieldGeometry.distanceFt(geometry.toField(drag.start));
      final moved = (drag.current - drag.start).distance > kTouchSlop;
      if (!moved) return '${at.round()} ft';
      final roll = FieldGeometry.distanceFt(geometry.toField(drag.current));
      return '${at.round()} ft → ${roll.round()} ft';
    }

    if (landing == null) return 'Tap the landing spot';
    final at = FieldGeometry.distanceFt(landing);
    final retrieved = draft.retrieved;
    if (retrieved == null) return '${at.round()} ft';
    final rolled = FieldGeometry.distanceFt(retrieved).round();
    return '${at.round()} ft → $rolled ft';
  }

  FieldGeometry _labelGeometry() {
    // The label re-derives world coordinates from the gesture's screen
    // points, so it needs the same geometry the canvas used. Rebuilt from
    // the current render box size — cheap, and never stale.
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(100, 100);
    return FieldGeometry(profile: FieldProfile.fastpitch12U, size: size);
  }
}
