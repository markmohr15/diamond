import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/events/pending_event.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/reach_at_commit.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/rules/play_line.dart';

/// What the open play would read as in the play log, said before it is
/// committed: the result in words beside the ✓ (§15.5, DIA-018b-2).
///
/// It is the play log's own sentence, not a second grammar. The draft's
/// events are appended to the visible stream under stand-in ids, the stream
/// is folded exactly as the play log folds it, and the sentences the play
/// *adds* are what comes back. Reading the difference, rather than the
/// pitch's whole line, keeps a steal after ball two from repeating whatever
/// that pitch already said.
///
/// It is what the ✓ would save **if the scorer entered nothing else**, so
/// the ✓'s own settling is applied first: a batter left on her walk-up
/// while a runner she pushed up is retired reads as the fielder's choice
/// the ✓ will record, not as the hit her presumed leg alone would derive.
/// [before] and [outs] are the fold's state ahead of the play, which the
/// draft cannot see.
///
/// Null when the draft can't be committed yet, when it would add nothing
/// worth saying, or when the ✓ would ask — "Safe at 1B — how?" or the
/// sacrifice — because any sentence then is a guess at the answer.
String? previewPlayLine(
  List<GameEvent> visible,
  PlayDraft draft, {
  required BaseState before,
  required int outs,
  PlayerLabel? label,
  bool evenIfAsking = false,
}) {
  if (!draft.committable) return null;
  if (!evenIfAsking) {
    if (reachAtCommit(draft, before) == ReachAtCommit.ask) return null;
    if (withReachSettled(draft, before).invitesSacrifice(outs: outs)) {
      return null;
    }
  }
  final (preview, _) = _previewEvents(visible, withReachSettled(draft, before));

  List<String> said(List<GameEvent> stream) {
    final lines = label == null
        ? playLines(foldOfficialScoring(stream))
        : playLines(foldOfficialScoring(stream), label: label);
    return [
      for (final line in lines)
        if (line.pitchEventId == draft.pitchEventId) ...line.sentences,
    ];
  }

  final already = said(visible);
  final added = [
    for (final sentence in said([...visible, ...preview]))
      if (!already.contains(sentence)) sentence,
  ];
  return added.isEmpty ? null : added.join(' ');
}

/// Each run the open play scores, with Diamond's earned and RBI rulings and
/// any answer the scorer has already given (§13.5 v0.77), keyed by the
/// scoring leg's [PlayEntry.key] — what the strip's run rows read.
///
/// Folded the same way [previewPlayLine] is, from what the ✓ would save if
/// nothing else were entered. Empty when the draft can't be committed yet.
Map<int, ScoredRun> previewRuns(
  List<GameEvent> visible,
  PlayDraft draft, {
  required BaseState before,
}) {
  if (!draft.committable) return const {};
  final (preview, idsByKey) = _previewEvents(
    visible,
    withReachSettled(draft, before),
  );
  final legKeyById = <String, int>{
    for (final MapEntry(:key, :value) in idsByKey.entries)
      if (key.startsWith('e')) value: int.parse(key.substring(1)),
  };
  return {
    for (final run in foldOfficialScoring([...visible, ...preview]).runs)
      if (legKeyById[run.eventId] case final legKey?) legKey: run,
  };
}

/// The draft's events as they would be appended, under stand-in ids, and
/// the stand-in id of each batch-local key.
(List<GameEvent>, Map<String, String>) _previewEvents(
  List<GameEvent> visible,
  PlayDraft draft,
) {
  final pending = draft.toEvents();
  String idOf(int i) => 'preview-$i';
  final idsByKey = {
    for (var i = 0; i < pending.length; i++)
      if (pending[i].localKey != null) pending[i].localKey!: idOf(i),
  };
  final last = visible.lastOrNull;
  final preview = [
    for (var i = 0; i < pending.length; i++)
      GameEvent(
        id: idOf(i),
        gameId: last?.gameId ?? '',
        seq: (last?.seq ?? 0) + 1 + i,
        deviceId: 'preview',
        createdBy: 'preview',
        wallClock: last?.wallClock ?? DateTime.fromMillisecondsSinceEpoch(0),
        type: pending[i].type,
        payload: resolveLocalRefs(pending[i].payload, idsByKey),
      ),
  ];
  return (preview, idsByKey);
}
