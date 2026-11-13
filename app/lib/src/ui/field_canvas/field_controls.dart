import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/play/play_preview.dart';
import 'package:diamond/src/play/possible_entries.dart';
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:diamond/src/ui/loop/pitch_flow.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/brand_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys the widget tests resolve against.
@visibleForTesting
const Key fieldLeaveKey = Key('fieldLeave');
@visibleForTesting
const Key fieldStartOverKey = Key('fieldStartOver');
@visibleForTesting
const Key fieldBackOneKey = Key('fieldBackOne');
@visibleForTesting
const Key fieldCommitKey = Key('fieldCommit');
@visibleForTesting
const Key leaveDiscardKey = Key('leaveDiscard');
@visibleForTesting
const Key leaveKeepKey = Key('leaveKeep');
@visibleForTesting
const Key fieldScoresAsKey = Key('fieldScoresAs');

/// Which pitch of its plate appearance the play hangs off — the number in
/// *Back to pitch 4's result*.
final pitchNumberProvider = FutureProvider.family<int?, String>((
  ref,
  pitchEventId,
) async {
  ref.watch(gameControllerProvider);
  final visible = await ref
      .read(eventStoreProvider)
      .readStream(ref.read(gameSessionProvider).gameId);
  return pitchNumberInPa(visible, pitchEventId);
});

/// The game's visible stream, for saying what the open play would score as.
/// Rebuilt whenever the fold moves.
final _visibleStreamProvider = FutureProvider<List<GameEvent>>((ref) {
  ref.watch(gameControllerProvider);
  return ref
      .read(eventStoreProvider)
      .readStream(ref.read(gameSessionProvider).gameId);
});

/// §15.5 v0.60: the field's own bar, every control labeled with what it does.
///
/// Before this the field had *Commit play* alone, and leaving it, starting
/// over and stepping back lived in the top bar as a bare ↺ and ✕ — which,
/// with tooltips that never appear on a tablet, could not be told apart
/// before pressing one (DIA-018). The two controls that throw work away sit
/// at the far end from the ✓.
class FieldControls extends ConsumerWidget {
  const FieldControls({
    required this.draft,
    required this.runnerLabels,
    required this.onCommit,
    super.key,
  });

  final PlayDraft draft;

  /// Token labels by runner id ("B", "1"…), for naming a step.
  final Map<String, String> runnerLabels;

  /// The surface's commit, which may ask a question first (§13.6).
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final play = ref.read(playDraftProvider.notifier);
    final previous = play.previousStep;
    // Something to lose: a step to take back, or a play reopened by undo
    // with everything already on it and no steps yet (§15.5 v0.63).
    final entered = previous != null || _hasContent(draft);
    final number = ref.watch(pitchNumberProvider(draft.pitchEventId));
    final pitch = number.valueOrNull == null
        ? "the pitch's"
        : "pitch ${number.valueOrNull}'s";

    // §15.5: what the ✓ would save, in the play log's own words, read
    // before it is pressed (DIA-018b-2). Mark's last several simulator
    // findings were all visible here first: "on the throw" where he meant an
    // error, and a throw from the RF that nobody made.
    final visible = ref.watch(_visibleStreamProvider).valueOrNull;
    final scoresAs = visible == null ? null : previewPlayLine(visible, draft);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandMetrics.spaceLg,
        vertical: BrandMetrics.spaceMd,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScoresAs(text: scoresAs),
          const SizedBox(height: BrandMetrics.spaceSm),
          _buttons(context, ref, play, previous, entered, pitch),
        ],
      ),
    );
  }

  Widget _buttons(
    BuildContext context,
    WidgetRef ref,
    PlayDraftController play,
    PlayDraft? previous,
    bool entered,
    String pitch,
  ) {
    // Four controls on a tablet in portrait: the theme's 28px button
    // padding is tightened here, and the two labels that describe *this*
    // play shrink with an ellipsis before anything overflows. The ✓ and
    // Start play over never shrink.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: _TwoLine(
                  buttonKey: fieldLeaveKey,
                  eyebrow: 'LEAVE FIELD',
                  label: draft.battedBall
                      ? 'Back to $pitch result'
                      : _betweenPitchesLabel(entered: entered),
                  icon: Icons.arrow_back,
                  onPressed: () => _leave(context, ref, pitch, asks: entered),
                ),
              ),
              const SizedBox(width: BrandMetrics.spaceMd),
              _HoldsItsPlace(
                shown: previous != null,
                child: OutlinedButton.icon(
                  key: fieldStartOverKey,
                  style: _compact,
                  onPressed: previous == null ? null : play.startOver,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Start play over'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: BrandMetrics.spaceXl),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: _HoldsItsPlace(
                  shown: previous != null,
                  child: _TwoLine(
                    buttonKey: fieldBackOneKey,
                    eyebrow: 'BACK ONE',
                    label: previous == null
                        ? 'Nothing to take back'
                        : describeStep(
                            before: previous,
                            after: draft,
                            runnerLabels: runnerLabels,
                          ),
                    icon: Icons.undo,
                    onPressed: previous == null ? null : play.stepUndo,
                  ),
                ),
              ),
              const SizedBox(width: BrandMetrics.spaceMd),
              _HoldsItsPlace(
                shown: draft.committable,
                child: FilledButton.icon(
                  key: fieldCommitKey,
                  style: _compact,
                  onPressed: draft.committable ? onCommit : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Commit play'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Between pitches Leave field means *done*: with nothing entered it
  /// closes the field, and with an entry it keeps it (Mark, 2026-11-10 —
  /// *"if you enter a steal and then say leave field, doesn't that assume
  /// you wanted the steal entered?"*). A steal hangs off nothing that has to
  /// be concretely entered the way a batted ball does.
  String _betweenPitchesLabel({required bool entered}) {
    if (!entered || !draft.committable) return 'Back to the call';
    return "Back to the call · keeps the ${_entryWords(draft) ?? 'entry'}";
  }

  /// Leave field asks only when leaving would lose something (14B). On a
  /// batted ball that is the play itself; between pitches it is only an
  /// entry too unfinished to keep, which it neither commits half-built nor
  /// throws away silently.
  Future<void> _leave(
    BuildContext context,
    WidgetRef ref,
    String pitch, {
    required bool asks,
  }) async {
    final flow = ref.read(pitchFlowProvider.notifier);
    if (!asks) {
      await flow.leaveField();
      return;
    }
    if (!draft.battedBall) {
      if (draft.committable) {
        onCommit();
        return;
      }
      final discard = await _ask(
        context,
        title: "This entry isn't finished",
        body: 'Finish it to keep it, or discard it and go back to the call.',
        keep: 'Finish it',
        drop: 'Discard it',
      );
      if (discard ?? false) await flow.leaveField();
      return;
    }
    final discard = await _ask(
      context,
      title: 'Back to $pitch result?',
      body:
          'This play is discarded. The pitch keeps its call and location, '
          'and you choose its result again.',
      keep: 'Keep this play',
      drop: 'Discard play',
    );
    if (discard ?? false) await flow.leaveField();
  }

  /// True to discard, false to stay.
  Future<bool?> _ask(
    BuildContext context, {
    required String title,
    required String body,
    required String keep,
    required String drop,
  }) {
    return showFieldDialog<bool>(
      context,
      title: title,
      children: (dialogContext) => [
        Text(body, style: Theme.of(dialogContext).textTheme.bodyLarge),
        const SizedBox(height: BrandMetrics.spaceXl),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              key: leaveKeepKey,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(keep),
            ),
            const SizedBox(width: BrandMetrics.spaceMd),
            FilledButton(
              key: leaveDiscardKey,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(drop),
            ),
          ],
        ),
      ],
    );
  }
}

/// Whether the draft holds anything the scorer entered beyond how it opened.
bool _hasContent(PlayDraft draft) =>
    draft.entries.length > draft.openingLegCount ||
    (draft.battedBall && (draft.trajectory != null || draft.landing != null));

/// What a between-pitch entry recorded, in the words Leave field uses —
/// the scorebook abbreviations for wild pitch and passed ball, as on undo.
String? _entryWords(PlayDraft draft) {
  for (final entry in draft.entries) {
    switch (entry) {
      case LegEntry(:final reasonOverride?):
        final words = switch (reasonOverride) {
          RunnerAdvanceReason.STOLEN_BASE => 'steal',
          RunnerAdvanceReason.WILD_PITCH => 'WP',
          RunnerAdvanceReason.PASSED_BALL => 'PB',
          RunnerAdvanceReason.DEFENSIVE_INDIFFERENCE => 'indifference',
          _ => null,
        };
        if (words != null) return words;
      case OutEntry(how: How.CAUGHT_STEALING):
        return 'caught stealing';
      case OutEntry(how: How.PICKED_OFF):
        return 'pickoff';
      default:
    }
  }
  return null;
}

/// §23.1 v0.63: a control that can't act is **not on screen**, rather than
/// greyed out (Mark, 2026-11-10 — *"if something is off, it should just not
/// be on the screen"*). It keeps its space, so nothing in the bar moves
/// mid-play when a control appears.
class _HoldsItsPlace extends StatelessWidget {
  const _HoldsItsPlace({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => Visibility(
    visible: shown,
    maintainSize: true,
    maintainAnimation: true,
    maintainState: true,
    child: child,
  );
}

/// §15.5's *SCORES AS* line over the bar (the 14A board): what the ✓ would
/// save, in the play log's sentence. Its space is kept while there is
/// nothing to say yet, so the buttons never jump when the play becomes
/// committable (§23.1 v0.63).
class _ScoresAs extends StatelessWidget {
  const _ScoresAs({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w700,
    );
    // Two lines, always: a long play wraps, and a bar that grew a line as
    // the play did would move the ✓ under the scorer's thumb.
    final lineHeight = MediaQuery.textScalerOf(
      context,
    ).scale(style.fontSize! * (style.height ?? 1.2));
    return SizedBox(
      height: lineHeight * 2,
      child: Visibility(
        visible: text != null,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // Sits on the sentence's first line rather than its top edge.
              padding: EdgeInsets.only(top: lineHeight * 0.3),
              child: Text(
                'SCORES AS',
                style: BrandType.eyebrow.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: BrandMetrics.spaceMd),
            Expanded(
              child: Text(
                text ?? '',
                key: fieldScoresAsKey,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The theme's button with less side padding, so four fit in one bar.
final ButtonStyle _compact = ButtonStyle(
  padding: WidgetStateProperty.all(
    const EdgeInsets.symmetric(
      horizontal: BrandMetrics.spaceLg,
      vertical: BrandMetrics.spaceMd,
    ),
  ),
);

/// An outlined button with a mono eyebrow over its label: *what kind of
/// control* above *what it will do this time*.
class _TwoLine extends StatelessWidget {
  const _TwoLine({
    required this.buttonKey,
    required this.eyebrow,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  /// On the button itself, so a test can read its `onPressed`.
  final Key buttonKey;

  final String eyebrow;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return OutlinedButton.icon(
      key: buttonKey,
      style: _compact,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: BrandType.eyebrow.copyWith(color: muted)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// What [after] holds that [before] did not — the words on Back one, so the
/// scorer knows what the tap removes before she makes it (§15.5 v0.60).
///
/// Step undo is snapshot-based, so there is no record of *which* action made
/// a step; this reads the difference instead. New entries are the common
/// case, and a throw adds a touch and a leg together, so the touch names it.
String describeStep({
  required PlayDraft before,
  required PlayDraft after,
  required Map<String, String> runnerLabels,
}) {
  final beforeKeys = {for (final e in before.entries) e.key};
  final added = [
    for (final e in after.entries)
      if (!beforeKeys.contains(e.key)) e,
  ];
  if (added.isNotEmpty) {
    final touch = added.whereType<TouchEntry>().firstOrNull;
    return _describe(touch ?? added.first, after, runnerLabels);
  }
  final trajectory = after.trajectory;
  if (trajectory != null && trajectory != before.trajectory) {
    return trajectoryLabel(trajectory);
  }
  if (!_same(after.landing, before.landing)) return 'The landing';
  if (!_same(after.endedAt, before.endedAt)) return 'Where it ended';

  final afterKeys = {for (final e in after.entries) e.key};
  final removed = before.entries.where((e) => !afterKeys.contains(e.key));
  if (removed.isNotEmpty) {
    return 'Removing ${_describe(removed.first, before, runnerLabels)}';
  }
  final beforeByKey = {for (final e in before.entries) e.key: e};
  for (final e in after.entries) {
    if (!identical(beforeByKey[e.key], e)) {
      return _describe(e, after, runnerLabels);
    }
  }
  if (after.heldBy != before.heldBy ||
      after.looseAfterKey != before.looseAfterKey) {
    return 'Ball loose';
  }
  if (after.offWall != before.offWall) return 'Off the wall';
  if (after.sacrifice != before.sacrifice) return 'Sacrifice';
  return 'The last change';
}

bool _same(FieldCoord? a, FieldCoord? b) =>
    (a == null && b == null) ||
    (a != null && b != null && a.x == b.x && a.y == b.y);

String _describe(
  PlayEntry entry,
  PlayDraft draft,
  Map<String, String> runnerLabels,
) {
  return switch (entry) {
    TouchEntry(:final position, :final touchType) =>
      '${positionAbbreviations[position] ?? position} '
          '${_touchWords[touchType] ?? _misplayWords(entry, draft)}',
    LegEntry(:final runnerId, :final to) =>
      '${_runner(runnerId, runnerLabels)} to ${_legBase[to] ?? to}',
    OutEntry(:final runnerId, :final atBase) =>
      '${_runner(runnerId, runnerLabels)} out at ${_outBase[atBase] ?? atBase}',
    RuleCallEntry(:final callType) => _callWords(callType),
  };
}

String _runner(String runnerId, Map<String, String> labels) {
  final label = labels[runnerId];
  if (label == null) return 'Runner';
  return label == 'B' ? 'Batter' : 'R$label';
}

String _callWords(CallType type) {
  final words = (callTypeValues.reverse[type] ?? 'rule call').replaceAll(
    '_',
    ' ',
  );
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

/// Clean plays read as what she did. Misplays are not here: they read as
/// the popup named them ([_misplayWords]), so Back one says *RF misplayed*
/// for what was entered as *Misplayed*.
const _touchWords = {
  TouchType.FIELDED: 'fielded it',
  TouchType.CAUGHT: 'catch',
  TouchType.RECEIVED_THROW: 'takes the throw',
  TouchType.DEFLECTED: 'deflection',
  TouchType.WILD_THROW: 'wild throw',
  TouchType.TAG_APPLIED: 'tag',
  TouchType.TAG_MISSED: 'missed tag',
};

String _misplayWords(TouchEntry touch, PlayDraft draft) {
  if (throwerInto(draft, touch) != null) {
    return touch.touchType == TouchType.DROPPED
        ? 'dropped the throw'
        : 'missed the throw';
  }
  return ballPlayLabel(
    touch.touchType,
    state: ballStateAt(draft, touch),
    trajectory: draft.trajectory,
  ).toLowerCase();
}

const _legBase = {1: '1st', 2: '2nd', 3: '3rd', 4: 'home'};
const _outBase = {1: '1B', 2: '2B', 3: '3B', 4: 'home'};
