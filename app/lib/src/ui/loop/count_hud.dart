import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/ui/loop/pitch_flow.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/brand_type.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:diamond/src/ui/theme/theme_mode_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
const Key countHudKey = Key('countHud');
@visibleForTesting
const Key countHudUndoKey = Key('countHudUndo');
@visibleForTesting
const Key countHudThemeKey = Key('countHudTheme');
@visibleForTesting
const Key countHudCancelKey = Key('countHudCancel');
@visibleForTesting
const Key countHudCountKey = Key('countHudCount');
@visibleForTesting
const Key countHudUnsureKey = Key('countHudUnsure');
@visibleForTesting
const Key countCorrectionSetKey = Key('countCorrectionSet');

/// The count strip (§11.2): balls–strikes, outs, inning — the invariant that
/// is never wrong, so it is always on screen while the loop runs.
///
/// **Dusk** when the count is uncertain (§12.5): an `unknown` pitch is in the
/// span and the projection refuses to guess. Not amber — v0.47 split the two
/// reservations apart, and amber is misplay alone now.
///
/// The treatment is a **tinted field with a saturated label**, not a wholesale
/// swap (§23.2). Size is why: chroma is what separates a reserved color from
/// Clay, but this strip is persistent and 84px tall, and a large area of high
/// chroma is unreadable after two innings. So the field takes a wash, and full
/// saturation goes to the two things that carry the meaning — the COUNT UNSURE
/// label and the separator between balls and strikes.
///
/// The label is also §23.1.7's non-color cue: the state is never signalled by
/// color alone, so a scorer who cannot separate violet from ink still reads
/// the words. Long-press on the count opens §12.5's CountCorrection sheet —
/// the checkpoint that clears it.
///
/// Undo lives here too: top-level, always visible, one event per tap (§6).
class CountHud extends ConsumerWidget {
  const CountHud({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final semantics = DiamondSemantics.of(context);
    final gs = ref.watch(gameControllerProvider).valueOrNull;

    final uncertain = gs?.uncertainCount ?? false;

    // A wash, not a fill. The saturated value is reserved for the label and
    // the separator below; at this size it would be a wall.
    final background = uncertain
        ? Color.alphaBlend(
            semantics.uncertainty.withValues(alpha: 0.16),
            scheme.surfaceContainerHigh,
          )
        : scheme.surfaceContainerHigh;

    // Ink either way. The old treatment switched this too, which is what made
    // the strip a solid block of chroma.
    final foreground = scheme.onSurface;

    // Optimistic while the check is in flight: the button guesses, and
    // `undoLast` re-reads the seal and is authoritative. Defaulting to
    // disabled would make the first tap after every action a dead one.
    final isDark = ref.watch(themeModeProvider).valueOrNull == ThemeMode.dark;
    final canCancel = ref.watch(canCancelProvider);
    final canUndo = ref.watch(canUndoProvider).valueOrNull ?? true;

    return Container(
      key: countHudKey,
      color: background,
      padding: const EdgeInsets.symmetric(
        horizontal: BrandMetrics.spaceLg,
        vertical: 10,
      ),
      child: Row(
        children: [
          // Long-press the count → §12.5's checkpoint sheet. The gesture the
          // spec names, on the thing it corrects.
          GestureDetector(
            key: countHudCountKey,
            onLongPress: gs == null ? null : () => _correctCount(context, ref),
            // Mono, because the count is the number most likely to be read
            // at a glance and it changes in place: 1-2 → 2-2 must not shift
            // its neighbors. A monospaced face gives that for free, which is
            // why the tabular-figures feature it used to carry is gone —
            // every digit already has the same advance width.
            //
            // Spans rather than one string so the separator can carry the
            // uncertainty on its own. It is the smallest mark on the strip
            // that still sits between the two numbers in question.
            child: Text.rich(
              gs == null
                  ? const TextSpan(text: '—')
                  : TextSpan(
                      children: [
                        TextSpan(text: '${gs.balls}'),
                        TextSpan(
                          text: '-',
                          style: uncertain
                              ? TextStyle(color: semantics.uncertainty)
                              : null,
                        ),
                        TextSpan(text: '${gs.strikes}'),
                      ],
                    ),
              style: text.displaySmall!.copyWith(color: foreground).code,
            ),
          ),
          if (uncertain) ...[
            const SizedBox(width: BrandMetrics.spaceMd),
            Text(
              // §23.1.7: the words are the cue that does not depend on
              // telling violet from ink.
              'COUNT UNSURE',
              key: countHudUnsureKey,
              style: BrandType.eyebrow.copyWith(color: semantics.uncertainty),
            ),
          ],
          const SizedBox(width: BrandMetrics.space2xl),
          Text(
            _outsLabel(gs),
            style: text.headlineMedium!.copyWith(color: foreground),
          ),
          const Spacer(),
          Text(
            _inningLabel(gs),
            // "▲3" is read as a tag, not as words — unlike `_outsLabel`
            // above it, which is the sentence "2 outs" and stays prose.
            style: text.headlineMedium!.copyWith(color: foreground).code,
          ),
          const SizedBox(width: 12),
          // Left of undo, per the design's top-right cluster (Mark,
          // 2026-09-01). A direct toggle rather than a settings surface:
          // light/dark does not belong to the pitch screens, and its real
          // home is a settings screen or a menu that may not be reachable
          // from here — so a sheet built to hold this one control was
          // scaffolding pretending to be a destination.
          IconButton(
            key: countHudThemeKey,
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: foreground,
            ),
            // Names what the tap *does*, not what is showing.
            tooltip: isDark ? 'Light' : 'Dark',
          ),
          // Disabled rather than inert when the plate appearance behind it
          // is sealed (§11.3 v0.54). A button that silently does nothing
          // reads as a bug, and this one declines often by design.
          IconButton(
            key: countHudUndoKey,
            // Through the pitch flow, not straight to the store: undoing a
            // pitch hands its call and location back to the loop (§11.3).
            onPressed: canUndo
                ? () => ref.read(pitchFlowProvider.notifier).undoLast()
                : null,
            icon: Icon(
              Icons.undo,
              color: canUndo ? foreground : foreground.withValues(alpha: 0.35),
            ),
            // Plain, both ways. An explanation here would live behind a
            // long-press on a greyed-out button, which nobody performs — the
            // disabled state has to carry the message by itself.
            tooltip: 'Undo',
          ),
          // §15.2 v0.54: ↺ and ✕ are one cluster, on every screen, per the
          // design — the ✕ that used to live in the field surface's own
          // chrome, where it was one of two undo-shaped controls on two
          // different layers.
          IconButton(
            key: countHudCancelKey,
            onPressed: canCancel ? () => _cancel(ref) : null,
            icon: Icon(
              Icons.close,
              color: canCancel ? foreground : foreground.withValues(alpha: .35),
            ),
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  /// The top bar's ✕ (Mark, 2026-09-01).
  ///
  /// On a batted ball it **starts the play over in place** — the entries go,
  /// the field stays up, and the trajectory question comes back to the front.
  /// Cancel is "I got this play wrong", not "throw the pitch away too", and
  /// leaving the field is undo's job.
  ///
  /// A between-pitch entry has no first question to return to, so there
  /// cancel is what it always was: close the field, recording nothing.
  void _cancel(WidgetRef ref) {
    final draft = ref.read(playDraftProvider).valueOrNull;
    if (draft == null) return;
    final play = ref.read(playDraftProvider.notifier);
    draft.battedBall ? play.startOver() : play.discard();
  }

  /// §12.5's CountCorrection sheet: "the scoreboard says 2-1, make it so."
  /// Prefilled with the current count, appended as an authoritative
  /// checkpoint — back-inference and the uncertainty flag are the fold's job.
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
          child: Text(label, style: Theme.of(context).textTheme.titleLarge),
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
            Text(
              'Set the count',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
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
