/// DIA-024b: the half-inning, read back.
///
/// Hidden by default and opened from the top bar (Mark, 2026-09-29) —
/// review rather than chrome. It answers *what did that score as*; the
/// other half of the need, *did that take what I meant*, is confirmation at
/// the ✓ and belongs to DIA-021's redesign.
///
/// Each run scored shows its earned and RBI rulings under its play (DIA-010).
/// Until a box score exists, this is the only place either ruling is
/// visible. Like everything else here, they are read, never entered.
library;

import 'dart:async';

import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/rules/logical_order.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/rules/play_line.dart';
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const Key playLogKey = Key('playLog');
const Key playLogEmptyKey = Key('playLogEmpty');
const Key playLogCloseKey = Key('playLogClose');

/// One run's ruling row, keyed by its scoring advance.
Key playLogRunKey(String runEventId) => Key('playLogRun-$runEventId');

/// The half-inning in front of her, in the order it happened.
///
/// Chronological because a scorebook is: the state carries forward, so
/// runners only make sense in sequence — read backwards, *r2 scored* sits
/// above *r2 advanced to third* and the reader has to reassemble the inning
/// herself. The newest play is reached by anchoring the viewport at the
/// end instead, which costs nothing (Mark, 2026-10-12).
///
/// Scoped rather than showing the whole game: the log is for the inning
/// being scored, and every play carries the inning it happened in
/// ([PlayRecord.inning]).
final playLogProvider = FutureProvider<List<PlayLine>>((ref) async {
  // Watched, not read: an append refolds the game, and the log has to
  // refold with it or it shows the play before last.
  final state = await ref.watch(gameControllerProvider.future);
  final store = ref.watch(eventStoreProvider);
  final session = ref.watch(gameSessionProvider);

  final visible = resolveVisibleLogicalOrder(
    await store.readRawStream(session.gameId),
  );
  final scoring = foldOfficialScoring(visible);
  final here = {
    for (final play in scoring.plays)
      if (play.inning == state.inning && play.half == state.half)
        play.pitchEventId,
  };
  return [
    for (final line in playLines(scoring))
      if (here.contains(line.pitchEventId)) line,
  ];
});

/// Opens the log. Nothing is entered from here — it is a reading surface,
/// so there is no result to wait for.
void showPlayLog(BuildContext context) {
  unawaited(
    showFieldDialog<void>(
      context,
      title: 'This half-inning',
      alignment: CrossAxisAlignment.start,
      children: (context) => [
        const PlayLogBody(),
        const SizedBox(height: BrandMetrics.spaceXl),
        // Nothing here commits anything, so the only way out is out — and
        // it is drawn rather than left to the barrier, which is invisible.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: playLogCloseKey,
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ),
      ],
    ),
  );
}

/// The list itself, separated so a golden can render it without a route.
class PlayLogBody extends ConsumerWidget {
  const PlayLogBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(playLogProvider);
    final text = Theme.of(context).textTheme;

    return lines.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (lines) {
        if (lines.isEmpty) {
          return Text(
            'Nothing scored yet this half-inning.',
            key: playLogEmptyKey,
            style: text.bodyMedium,
          );
        }
        // Selectable across the whole log rather than line by line, so a
        // drag can take several plays at once — which is the shape of the
        // question being asked when someone copies a scoring line out.
        return SelectionArea(
          child: ConstrainedBox(
            // A half-inning can run long. Bounded so the dialog cannot grow
            // past the screen, and `reverse` parks the viewport at the end,
            // so the play she just entered is what she sees without undoing
            // the reading order to get it.
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                key: playLogKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final line in lines) ...[
                    // One paragraph per happening. A play's second sentence —
                    // the error — wraps under the first rather than starting a
                    // row of its own, because it is the same play.
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: BrandMetrics.spaceMd,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.text, style: text.bodyLarge),
                          for (final run in line.runs) _RunRow(run: run),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A run's rulings in one line under its play: *b1 · earned · RBI b2*.
///
/// Quiet, because the play's sentence is what the log is for. The accent goes
/// on *edited* alone: it is the one datum here the scorer put in herself, and
/// it is what she is looking for when she comes back to check.
///
/// Read-only. Overrides are entered with the play (§13.5 v0.76), and the play
/// log edits nothing (Mark, 2026-11-24).
class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});

  final ScoredRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Not `colorScheme.primary`: that is the raw accent, which as text in dark
    // mode is 2.2:1 against the dialog (§23.3). The outlined button's label is
    // the accent already lifted against this same surface (the dialog's
    // `surfaceContainerLow`), so this reads it rather than lifting it again.
    final edited =
        theme.outlinedButtonTheme.style?.foregroundColor?.resolve(const {}) ??
        theme.colorScheme.primary;
    return Text.rich(
      key: playLogRunKey(run.eventId),
      TextSpan(
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text:
                '${run.runnerId} · '
                '${run.earned ? 'earned' : 'unearned'} · '
                '${run.rbi ? 'RBI ${run.batterId}' : 'no RBI'}',
          ),
          if (run.edited)
            TextSpan(
              text: ' · edited',
              style: TextStyle(color: edited),
            ),
        ],
      ),
    );
  }
}
