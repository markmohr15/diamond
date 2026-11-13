import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/events/pending_event.dart';
import 'package:diamond/src/play/play_draft.dart';
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
/// Null when the draft can't be committed yet, or when it would add nothing
/// worth saying.
String? previewPlayLine(
  List<GameEvent> visible,
  PlayDraft draft, {
  PlayerLabel? label,
}) {
  if (!draft.committable) return null;
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

  List<String> said(List<GameEvent> stream) {
    final lines = label == null
        ? playLines(foldOfficialScoring(stream))
        : playLines(foldOfficialScoring(stream), label: label);
    return [
      for (final line in lines)
        if (line.pitchEventId == draft.pitchEventId) ...line.sentences,
    ];
  }

  final before = said(visible);
  final after = said([...visible, ...preview]);
  final added = [
    for (final sentence in after)
      if (!before.contains(sentence)) sentence,
  ];
  return added.isEmpty ? null : added.join(' ');
}
