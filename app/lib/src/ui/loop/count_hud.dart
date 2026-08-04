import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/ui/loop/pitch_flow.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
const Key countHudKey = Key('countHud');
@visibleForTesting
const Key countHudUndoKey = Key('countHudUndo');
@visibleForTesting
const Key countHudCountKey = Key('countHudCount');
@visibleForTesting
const Key countCorrectionSetKey = Key('countCorrectionSet');

/// The count strip (§11.2): balls–strikes, outs, inning — the invariant that
/// is never wrong, so it is always on screen while the loop runs.
///
/// Amber when the count is uncertain (§12.5): an `unknown` pitch is in the
/// span and the projection refuses to guess. The treatment is §23.2's
/// uncertainty reservation — background and text both switch, because a thin
/// accent line is exactly what sunlight erases. Long-press on the count opens
/// §12.5's CountCorrection sheet — the checkpoint that clears it.
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
          // Long-press the count → §12.5's checkpoint sheet. The gesture the
          // spec names, on the thing it corrects.
          GestureDetector(
            key: countHudCountKey,
            onLongPress: gs == null ? null : () => _correctCount(context, ref),
            child: Text(
              gs == null ? '—' : '${gs.balls}-${gs.strikes}',
              style: TextStyle(
                color: foreground,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                // Tabular figures: 1-2 → 2-2 must not shift its neighbors.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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

  /// §12.5's CountCorrection sheet: "the scoreboard says 2-1, make it so."
  /// Prefilled with the current count, appended as an authoritative
  /// checkpoint — back-inference and the amber flag are the fold's job.
  Future<void> _correctCount(BuildContext context, WidgetRef ref) async {
    final gs = ref.read(gameControllerProvider).valueOrNull;
    if (gs == null) return;

    final result = await showModalBottomSheet<({int balls, int strikes})>(
      context: context,
      builder: (context) =>
          _CountCorrectionSheet(balls: gs.balls, strikes: gs.strikes),
    );
    if (result == null) return;
    await ref
        .read(pitchFlowProvider.notifier)
        .correctCount(balls: result.balls, strikes: result.strikes);
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

/// The checkpoint entry: balls and strikes as chips, prefilled from the
/// current count. Deliberately tiny — this is used mid-chaos (§12.5), so it
/// is two rows and one button, not a form.
class _CountCorrectionSheet extends StatefulWidget {
  const _CountCorrectionSheet({required this.balls, required this.strikes});

  final int balls;
  final int strikes;

  @override
  State<_CountCorrectionSheet> createState() => _CountCorrectionSheetState();
}

class _CountCorrectionSheetState extends State<_CountCorrectionSheet> {
  late int _balls = widget.balls;
  late int _strikes = widget.strikes;

  Widget _chipRow({
    required String label,
    required int max,
    required int selected,
    required ValueChanged<int> onSelected,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(fontSize: 18)),
        ),
        for (var i = 0; i <= max; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text('$i'),
              selected: selected == i,
              onSelected: (_) => onSelected(i),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Set the count',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _chipRow(
              label: 'Balls',
              max: 3,
              selected: _balls,
              onSelected: (v) => setState(() => _balls = v),
            ),
            const SizedBox(height: 8),
            _chipRow(
              label: 'Strikes',
              max: 2,
              selected: _strikes,
              onSelected: (v) => setState(() => _strikes = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: countCorrectionSetKey,
              onPressed: () =>
                  Navigator.of(context).pop((balls: _balls, strikes: _strikes)),
              child: Text('Make it $_balls-$_strikes'),
            ),
          ],
        ),
      ),
    );
  }
}
