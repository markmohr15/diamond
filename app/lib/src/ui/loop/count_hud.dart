import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
const Key countHudKey = Key('countHud');
@visibleForTesting
const Key countHudUndoKey = Key('countHudUndo');

/// The count strip (§11.2): balls–strikes, outs, inning — the invariant that
/// is never wrong, so it is always on screen while the loop runs.
///
/// Amber when the count is uncertain (§12.5): an `unknown` pitch is in the
/// span and the projection refuses to guess. The treatment is §23.2's
/// uncertainty reservation — background and text both switch, because a thin
/// accent line is exactly what sunlight erases. Long-press → CountCorrection
/// sheet is DIA-007b; the gesture surface is already this whole strip.
///
/// Undo lives here too: top-level, always visible, one event per tap (§6).
class CountHud extends ConsumerWidget {
  const CountHud({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final semantics = DiamondSemantics.of(context);
    final gs = ref.watch(gameControllerProvider).valueOrNull;

    final uncertain = gs?.uncertainCount ?? false;
    final background = uncertain
        ? semantics.uncertainty
        : scheme.surfaceContainerHigh;
    final foreground = uncertain ? semantics.onUncertainty : scheme.onSurface;

    return Container(
      key: countHudKey,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            gs == null ? '—' : '${gs.balls}-${gs.strikes}',
            style: TextStyle(
              color: foreground,
              fontSize: 34,
              fontWeight: FontWeight.bold,
              // Tabular figures: 1-2 → 2-2 must not shift its neighbors.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 24),
          Text(
            _outsLabel(gs),
            style: TextStyle(color: foreground, fontSize: 20),
          ),
          const Spacer(),
          Text(
            _inningLabel(gs),
            style: TextStyle(color: foreground, fontSize: 20),
          ),
          const SizedBox(width: 12),
          IconButton(
            key: countHudUndoKey,
            onPressed: () =>
                ref.read(gameControllerProvider.notifier).undoLast(),
            icon: Icon(Icons.undo, color: foreground),
            tooltip: 'Undo',
          ),
        ],
      ),
    );
  }

  String _outsLabel(GameState? gs) {
    final outs = gs?.outs ?? 0;
    return outs == 1 ? '1 out' : '$outs outs';
  }

  String _inningLabel(GameState? gs) {
    if (gs == null || gs.half == null) return '';
    final arrow = gs.half == Half.TOP ? '▲' : '▼';
    return '$arrow${gs.inning}';
  }
}
