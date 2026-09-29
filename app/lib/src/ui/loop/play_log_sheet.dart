/// DIA-024b: the half-inning, read back.
///
/// Hidden by default and opened from the top bar (Mark, 2026-09-29) —
/// review rather than chrome. It answers *what did that score as*; the
/// other half of the need, *did that take what I meant*, is confirmation at
/// the ✓ and belongs to DIA-021's redesign.
library;

import 'dart:async';

import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/rules/logical_order.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/rules/play_line.dart';
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Key playLogKey = Key('playLog');
const Key playLogEmptyKey = Key('playLogEmpty');
const Key playLogCloseKey = Key('playLogClose');

/// The half-inning in front of her, newest first.
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
    for (final line in playLines(scoring).reversed)
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
        return Column(
          key: playLogKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in lines) ...[
              // One paragraph per happening. A play's second sentence — the
              // error — wraps under the first rather than starting a row of
              // its own, because it is the same play.
              Padding(
                padding: const EdgeInsets.only(bottom: BrandMetrics.spaceMd),
                child: Text(line.text, style: text.bodyLarge),
              ),
            ],
          ],
        );
      },
    );
  }
}
