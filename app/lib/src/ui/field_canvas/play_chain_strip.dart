import 'dart:async';

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/play/play_preview.dart';
import 'package:diamond/src/play/possible_entries.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/ui/dialog/dialog_parts.dart';
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/field_canvas/play_stream.dart';
import 'package:diamond/src/ui/field_canvas/review_card.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
Key chainNodeKey(int entryKey) => Key('chainNode-$entryKey');
@visibleForTesting
Key chainChipKey(String id) => Key('chainChip-$id');
@visibleForTesting
const Key chainRemoveKey = Key('chainRemove');
@visibleForTesting
const Key chainBallNodeKey = Key('chainBall');

/// Labels for what a touch node can be retyped to (§15.3's menu). Which of
/// them a node offers is [retypeChoices]'s call, not this map's.
const _misplayLabels = <TouchType, String>{
  TouchType.DROPPED: 'Dropped',
  TouchType.BOOTED: 'Booted',
  TouchType.BOBBLED: 'Bobbled',
  TouchType.DEFLECTED: 'Deflected',
  TouchType.WILD_THROW: 'Wild throw',
  TouchType.MISSED_CATCH: 'Missed catch',
  TouchType.TAG_MISSED: 'Missed tag',
};

const _arrivalLabels = <ReceivedQuality, String>{
  ReceivedQuality.CLEAN: 'Clean',
  ReceivedQuality.SHORT_HOP: 'Short hop',
  ReceivedQuality.HIGH: 'High',
  ReceivedQuality.WIDE: 'Wide',
};

/// An out's `how` in words, for the runner row and its menu.
const _howWords = <How, String>{
  How.FORCE: 'force',
  How.TAG: 'tagged',
  How.FLY_OUT: 'caught',
  How.INFIELD_FLY: 'infield fly',
  How.APPEAL: 'appeal',
  How.CAUGHT_STEALING: 'caught stealing',
  How.PICKED_OFF: 'picked off',
  How.LEFT_EARLY: 'left early',
  How.LOOK_BACK_RULE: 'look-back rule',
  How.INTERFERENCE: 'interference',
  How.BATTED_BALL_CONTACT: 'struck by batted ball',
  How.STRIKEOUT: 'strikeout',
  How.STRIKEOUT_D3_K_THROW: 'strikeout',
  How.ABANDONED: 'abandoned',
  How.BATTER_OUT_OF_BOX: 'out of the box',
};

/// Labels for an out's `how` that [possibleHows] never offers as a choice
/// but an out can already carry — set by the ⚖ or by its own path — so the
/// sheet can still show what she is out on.
const _otherHowLabels = <How, String>{
  How.INTERFERENCE: 'Interference',
  How.BATTED_BALL_CONTACT: 'Struck by batted ball',
};

const _callWords = <CallType, String>{
  CallType.OBSTRUCTION: 'obstruction',
  CallType.INTERFERENCE_RUNNER: 'interference',
  CallType.INFIELD_FLY: 'infield fly',
};

/// §15.2's play chain strip (v0.77, board 16A): the play as steps, every
/// part a button that says what happened.
///
/// The ball leads; each touch is *fielder · verb*, filled with Rosin when it
/// is a misplay (§23.2) and underlined when a throw arrived badly
/// (information, not fault). Runner consequences hang beneath the step that
/// caused them, in words — *Batter safe at 1st*, *R3 scored* — and a run's
/// row carries its earned and RBI rulings (§13.5). Tapping any of them opens
/// its menu (§15.3, §23.7); there is no "+" chip any more, because the
/// control is the step.
class PlayChainStrip extends ConsumerStatefulWidget {
  const PlayChainStrip({
    required this.draft,
    required this.runnerLabels,
    super.key,
  });

  final PlayDraft draft;

  /// runnerId → short token label ('B', '1', '2', '3') — same labels the
  /// canvas tokens wear.
  final Map<String, String> runnerLabels;

  @override
  ConsumerState<PlayChainStrip> createState() => _PlayChainStripState();
}

class _PlayChainStripState extends ConsumerState<PlayChainStrip> {
  final _scroll = ScrollController();
  int _lastHeadCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// §15.2 v0.77: a play that outgrows the strip scrolls, and the newest
  /// step stays in view — it is the one the scorer just made.
  void _keepNewestInView(int heads) {
    if (heads <= _lastHeadCount) {
      _lastHeadCount = heads;
      return;
    }
    _lastHeadCount = heads;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 1),
          curve: Curves.linear,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    // Columns: the ball first, then each touch/rule-call in entry order.
    // Consequences hang beneath their enabler (legs) / putout credit
    // (outs); unattributed ones hang beneath the ball.
    final heads = <int?>[
      null,
      for (final entry in draft.entries)
        if (entry is TouchEntry || entry is RuleCallEntry) entry.key,
    ];
    final consequencesByHead = <int?, List<PlayEntry>>{};
    for (final entry in draft.entries) {
      final head = switch (entry) {
        LegEntry(enabledByKey: final e) => heads.contains(e) ? e : null,
        OutEntry(putoutKey: final p) => heads.contains(p) ? p : null,
        _ => -1, // heads themselves
      };
      if (head == -1) continue;
      (consequencesByHead[head] ??= []).add(entry);
    }
    _keepNewestInView(heads.length);

    final runs = _runs(draft);

    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        BrandMetrics.spaceLg,
        BrandMetrics.spaceSm,
        BrandMetrics.spaceLg,
        BrandMetrics.spaceMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, head) in heads.indexed) ...[
            if (index > 0) const _Arrow(),
            _column(
              context,
              draft,
              head,
              index,
              consequencesByHead[head] ?? const [],
              runs,
            ),
          ],
        ],
      ),
    );
  }

  /// Each run on the play, with Diamond's rulings and the scorer's answer,
  /// by its scoring leg (§13.5 v0.77). Empty while the stream is loading or
  /// the play can't be committed yet; the run rows then read without them.
  Map<int, ScoredRun> _runs(PlayDraft draft) {
    final visible = ref.watch(visibleStreamProvider).valueOrNull;
    final fold = ref.watch(gameControllerProvider).valueOrNull;
    if (visible == null || fold == null) return const {};
    return previewRuns(visible, draft, before: fold.bases);
  }

  Widget _column(
    BuildContext context,
    PlayDraft draft,
    int? headKey,
    int stepNumber,
    List<PlayEntry> consequences,
    Map<int, ScoredRun> runs,
  ) {
    final head = headKey == null ? null : draft.entryByKey(headKey);
    final step = switch (head) {
      null => _BallStep(
        trajectory: draft.trajectory,
        battedBall: draft.battedBall,
        onTap: draft.battedBall ? () => _showBallMenu(context) : null,
      ),
      final TouchEntry touch => _StepButton(
        key: chainNodeKey(touch.key),
        number: stepNumber,
        who: positionAbbreviations[touch.position] ?? '${touch.position}',
        verb: _verb(draft, touch),
        misplay: touch.isMisplay,
        underline:
            touch.receivedQuality != null &&
            touch.receivedQuality != ReceivedQuality.CLEAN,
        onTap: () => showTouchSheet(context, ref, widget.draft, touch),
      ),
      final RuleCallEntry call => _StepButton(
        key: chainNodeKey(call.key),
        number: stepNumber,
        who: 'Call',
        verb:
            _callWords[call.callType] ?? callTypeValues.reverse[call.callType]!,
        onTap: () => _showRuleCallMenu(context, call),
      ),
      _ => const SizedBox.shrink(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        step,
        if (consequences.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(
              left: BrandMetrics.spaceMd,
              top: BrandMetrics.spaceSm,
            ),
            padding: const EdgeInsets.only(left: BrandMetrics.spaceMd),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, consequence) in consequences.indexed) ...[
                  if (i > 0) const SizedBox(height: BrandMetrics.spaceXs + 2),
                  _consequenceRow(context, consequence, runs),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _consequenceRow(
    BuildContext context,
    PlayEntry entry,
    Map<int, ScoredRun> runs,
  ) {
    return switch (entry) {
      LegEntry(to: 4) => _RunnerRow(
        key: chainNodeKey(entry.key),
        words: '${_who(entry.runnerId)} scored',
        run: true,
        rulings: runs[entry.key],
        onTap: () => _showLegMenu(context, entry, runs[entry.key]),
      ),
      LegEntry() => _RunnerRow(
        key: chainNodeKey(entry.key),
        words: _legWords(entry),
        onTap: () => _showLegMenu(context, entry, null),
      ),
      OutEntry() => _RunnerRow(
        key: chainNodeKey(entry.key),
        words: '${_who(entry.runnerId)} out at ${_baseWord(entry.atBase)}',
        detail: _howWords[entry.how],
        out: true,
        onTap: () => _showOutMenu(context, entry),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  /// *Batter*, *R1* — the token's own label, as a word.
  String _who(String runnerId) {
    final label = widget.runnerLabels[runnerId];
    if (label == null) return 'Runner';
    return label == 'B' ? 'Batter' : 'R$label';
  }

  String _legWords(LegEntry leg) {
    final who = _who(leg.runnerId);
    if (leg.from == 0 && leg.to == 1) return '$who safe at 1st';
    return '$who to ${_baseWord(leg.to)}';
  }

  static String _baseWord(int base) => switch (base) {
    1 => '1st',
    2 => '2nd',
    3 => '3rd',
    _ => 'home',
  };

  /// The ball's step opens how it was hit, and the calls on the ball that
  /// are legal now — today the infield fly (§15.3).
  void _showBallMenu(BuildContext context) {
    final draft = widget.draft;
    final controller = ref.read(playDraftProvider.notifier);
    final infieldFly = _offersInfieldFly(draft);
    showFieldDialog<void>(
      context,
      title: draft.trajectory == null
          ? 'The ball'
          : trajectoryLabel(draft.trajectory!),
      question: infieldFly
          ? 'How was it hit, or a call on the ball?'
          : 'How was it hit?',
      children: (dialogContext) => [
        TrajectoryRow(
          selected: draft.trajectory,
          bunted: draft.bunted,
          onChosen: (trajectory) {
            unawaited(controller.setTrajectory(trajectory));
            Navigator.pop(dialogContext);
          },
        ),
        if (infieldFly) ...[
          const DialogSection('A call on the ball'),
          AnswerGrid(
            columns: 1,
            children: [
              AnswerButton(
                key: chainChipKey('infield_fly'),
                label: 'Infield fly',
                detail: 'the batter is out, and nobody is forced',
                onPressed: () {
                  Navigator.pop(dialogContext);
                  unawaited(controller.declareInfieldFly());
                },
              ),
            ],
          ),
        ],
        const DialogDone(),
      ],
    );
  }

  bool _offersInfieldFly(PlayDraft draft) {
    final game = ref.read(gameControllerProvider).valueOrNull;
    if (game == null) return false;
    return offersInfieldFly(draft, outs: game.outs, bases: game.bases);
  }

  void _showRuleCallMenu(BuildContext context, RuleCallEntry call) {
    final words =
        _callWords[call.callType] ?? callTypeValues.reverse[call.callType]!;
    showFieldDialog<void>(
      context,
      title: 'Call · $words',
      question: 'A rule call on this play.',
      children: (dialogContext) => [
        DialogDone(leading: _removeAction(dialogContext, ref, call.key)),
      ],
    );
  }

  /// A runner's menu (§15.3): which step put her there, and the rule calls
  /// that belong on a runner. A run's row adds its earned and RBI rulings
  /// on top (§13.5 v0.77), the reason the scorer opens it.
  void _showLegMenu(BuildContext context, LegEntry leg, ScoredRun? run) {
    final draft = widget.draft;
    final controller = ref.read(playDraftProvider.notifier);
    final steps = [
      for (final (index, entry) in draft.entries.indexed)
        if (entry is TouchEntry) (index, entry),
    ];
    final title = leg.to == 4 ? '${_who(leg.runnerId)} scored' : _legWords(leg);
    showFieldDialog<void>(
      context,
      title: title,
      question: run != null
          ? 'Earned, an RBI, and what put her there?'
          : 'What put her there, and was there a call?',
      children: (dialogContext) => [
        if (run != null) ...[
          const DialogSection('Earned and RBI'),
          RunRulingsAnswers(
            run: run,
            keyOf: chainChipKey,
            onChanged: (ruling) {
              unawaited(controller.setRunRuling(leg.key, ruling));
              Navigator.pop(dialogContext);
            },
          ),
        ],
        const DialogSection('On which step'),
        AnswerGrid(
          children: [
            AnswerButton(
              key: chainChipKey('enabler-none'),
              label: draft.battedBall ? 'The batted ball' : 'On her own',
              selected: leg.enabledByKey == null,
              onPressed: () {
                unawaited(controller.reattributeLeg(leg.key, null));
                Navigator.pop(dialogContext);
              },
            ),
            for (final (_, touch) in steps)
              AnswerButton(
                key: chainChipKey('enabler-${touch.key}'),
                label:
                    '${positionAbbreviations[touch.position] ?? touch.position}'
                    ' ${_verb(draft, touch)}',
                detail: 'step ${_stepNumberOf(draft, touch.key)}',
                selected: leg.enabledByKey == touch.key,
                tone: touch.isMisplay ? AnswerTone.misplay : AnswerTone.ink,
                onPressed: () {
                  unawaited(controller.reattributeLeg(leg.key, touch.key));
                  Navigator.pop(dialogContext);
                },
              ),
          ],
        ),
        ..._ruleCalls(dialogContext, leg.key),
        DialogDone(leading: _removeAction(dialogContext, ref, leg.key)),
      ],
    );
  }

  /// An out's menu offers the same outs the OUT dialog did (§4.3) — a
  /// between-pitch out is never a force, and neither is a runner's out
  /// after a catch (DIA-019 H). Only outs entered before this one count
  /// against her force; see [possibleHows]. Her current `how` always shows.
  void _showOutMenu(BuildContext context, OutEntry out) {
    final controller = ref.read(playDraftProvider.notifier);
    final bases =
        ref.read(gameControllerProvider).valueOrNull?.bases ?? BaseState.empty;
    final possible = [
      for (final (_, label, how) in possibleHows(
        widget.draft,
        out.runnerId,
        out.atBase,
        bases,
        editingKey: out.key,
      ))
        (label, how),
    ];
    final hows = [
      if (!possible.any((choice) => choice.$2 == out.how))
        (_otherHowLabels[out.how] ?? howValues.reverse[out.how]!, out.how),
      ...possible,
    ];
    showFieldDialog<void>(
      context,
      title: '${_who(out.runnerId)} out at ${_baseWord(out.atBase)}',
      question: 'How was she out?',
      children: (dialogContext) => [
        AnswerGrid(
          children: [
            for (final (label, how) in hows)
              AnswerButton(
                key: chainChipKey(howValues.reverse[how]!),
                label: label,
                selected: out.how == how,
                onPressed: () {
                  unawaited(controller.setOutHow(out.key, how));
                  Navigator.pop(dialogContext);
                },
              ),
          ],
        ),
        ..._ruleCalls(dialogContext, out.key),
        DialogDone(leading: _removeAction(dialogContext, ref, out.key)),
      ],
    );
  }

  /// §15.3 v0.43: the ⚖ calls are baserunning facts, so they live on the
  /// runner menus — attached to this movement, inserted into the chain just
  /// before it — never on a standing button.
  List<Widget> _ruleCalls(BuildContext dialogContext, int consequenceKey) {
    final controller = ref.read(playDraftProvider.notifier);
    return [
      const DialogSection('A rule call'),
      AnswerGrid(
        children: [
          for (final callType in const [
            CallType.OBSTRUCTION,
            CallType.INTERFERENCE_RUNNER,
          ])
            AnswerButton(
              key: chainChipKey(callTypeValues.reverse[callType]!),
              label: callType == CallType.OBSTRUCTION
                  ? 'Obstruction'
                  : 'Interference',
              onPressed: () async {
                Navigator.pop(dialogContext);
                final against = await showPositionPicker(
                  context,
                  callType == CallType.OBSTRUCTION
                      ? 'Obstructed by?'
                      : 'Interfered with?',
                );
                if (against == null) return;
                await controller.attachRuleCall(
                  consequenceKey,
                  callType,
                  againstPosition: against,
                );
              },
            ),
        ],
      ),
    ];
  }
}

/// The step's position in the strip: 1 for the first touch or call.
int _stepNumberOf(PlayDraft draft, int key) {
  var n = 0;
  for (final entry in draft.entries) {
    if (entry is TouchEntry || entry is RuleCallEntry) n++;
    if (entry.key == key) return n;
  }
  return n;
}

/// What a fielder did, as the step reads it: *booted*, *threw wild*, *took
/// the throw*. A reception keeps the throw's vocabulary (*dropped*); a play
/// on the ball reads as the popup offered it (DIA-025), so a pitch that got
/// away is *picked up*, never *fielded*.
String _verb(PlayDraft draft, TouchEntry touch) {
  if (touch.touchType == TouchType.WILD_THROW) return 'threw wild';
  final label = throwerInto(draft, touch) != null
      ? (_misplayLabels[touch.touchType] ??
            ballPlayLabel(
              touch.touchType,
              state: ballStateAt(draft, touch),
              trajectory: draft.trajectory,
            ))
      : ballPlayLabel(
          touch.touchType,
          state: ballStateAt(draft, touch),
          trajectory: draft.trajectory,
        );
  return label.toLowerCase();
}

String _positionName(TouchEntry touch) =>
    positionAbbreviations[touch.position] ?? '${touch.position}';

String _capitalized(String words) =>
    words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);

Widget _removeAction(BuildContext dialogContext, WidgetRef ref, int key) {
  return QuietAction(
    key: chainRemoveKey,
    label: 'Remove this step',
    icon: Icons.delete_outline,
    onPressed: () {
      unawaited(ref.read(playDraftProvider.notifier).removeEntry(key));
      Navigator.pop(dialogContext);
    },
  );
}

/// A retype choice's words: a reception keeps the throw's vocabulary
/// (*Dropped*, *Missed catch*, *Missed tag*); a play on the ball reads as
/// the popup offered it, so a touch entered as *Misplayed* is not renamed
/// *Booted* here (DIA-025).
String _retypeLabel(PlayDraft draft, TouchEntry touch, TouchType type) =>
    throwerInto(draft, touch) != null
    ? _misplayLabels[type]!
    : ballPlayLabel(
        type,
        state: ballStateAt(draft, touch),
        trajectory: draft.trajectory,
      );

/// §15.3's menu on a touch step (board 16E): the misplay set beside the
/// clean answer, arrival quality on a reception, *the throw was wild*, and
/// removal. Opened from the step, and from the canvas by a tap on the
/// receiver of a throw (§15.1 v0.72).
void showTouchSheet(
  BuildContext context,
  WidgetRef ref,
  PlayDraft draft,
  TouchEntry touch,
) {
  final controller = ref.read(playDraftProvider.notifier);
  final position = positionAbbreviations[touch.position] ?? touch.position;
  final thrower = throwerInto(draft, touch);
  final clean = cleanCounterpart(draft, touch);
  // Retyping is another way in to the popup's vocabulary, so it offers only
  // what the popup could have — a catcher chasing a pitch cannot be retyped
  // to *Booted* any more than she could be entered that way (DIA-019 H).
  final misplays = retypeChoices(draft, touch);
  void retype(BuildContext dialogContext, TouchType type) {
    unawaited(controller.setTouchType(touch.key, type));
    Navigator.pop(dialogContext);
  }

  showFieldDialog<void>(
    context,
    title: '$position · step ${_stepNumberOf(draft, touch.key)}',
    question: thrower != null
        ? 'How did the throw arrive, and did she hold it?'
        : 'What did she do with it?',
    children: (dialogContext) => [
      AnswerGrid(
        children: [
          if (clean != null)
            AnswerButton(
              key: chainChipKey(touchTypeValues.reverse[clean]!),
              label: thrower != null
                  ? 'Caught it'
                  : ballPlayLabel(
                      clean,
                      state: ballStateAt(draft, touch),
                      trajectory: draft.trajectory,
                    ),
              detail: 'clean',
              selected: touch.touchType == clean,
              onPressed: () => retype(dialogContext, clean),
            )
          else if (!touch.isMisplay && touch.touchType != TouchType.DEFLECTED)
            // What is recorded now, even when there is no going back to it
            // from a misplay: a menu with nothing selected says nothing.
            AnswerButton(
              key: chainChipKey(touchTypeValues.reverse[touch.touchType]!),
              label: _capitalized(_verb(draft, touch)),
              selected: true,
              onPressed: () => Navigator.pop(dialogContext),
            ),
          for (final type in misplays)
            AnswerButton(
              key: chainChipKey(touchTypeValues.reverse[type]!),
              label: _retypeLabel(draft, touch, type),
              detail: type == TouchType.DEFLECTED
                  ? 'not an error, the ball kept going'
                  : null,
              selected: touch.touchType == type,
              tone: misplayTouchTypes.contains(type)
                  ? AnswerTone.misplay
                  : AnswerTone.ink,
              onPressed: () => retype(dialogContext, type),
            ),
        ],
      ),
      if (thrower != null) ...[
        const DialogSection('It arrived'),
        AnswerGrid(
          columns: 4,
          children: [
            for (final MapEntry(key: quality, value: label)
                in _arrivalLabels.entries)
              AnswerButton(
                key: chainChipKey(receivedQualityValues.reverse[quality]!),
                label: label,
                selected:
                    (touch.receivedQuality ?? ReceivedQuality.CLEAN) == quality,
                onPressed: () {
                  unawaited(controller.setReceivedQuality(touch.key, quality));
                  Navigator.pop(dialogContext);
                },
              ),
          ],
        ),
        // §13.2: `wild_throw` on a node means *this fielder threw it away*,
        // and the grammar is right — but the throw **arrives** badly, and
        // the receiver's node is the one that just appeared, so that is
        // where the finger goes. So the receiving step offers the question
        // in the direction the scorer is looking, and retypes the thrower.
        const DialogSection('Nobody caught it'),
        AnswerGrid(
          columns: 1,
          children: [
            AnswerButton(
              key: chainChipKey('throw_was_wild'),
              label: 'The throw was wild',
              detail:
                  "it's on the ${_positionName(thrower)}, "
                  'and this catch goes away',
              onPressed: () {
                unawaited(
                  controller.markThrowWild(
                    throwerKey: thrower.key,
                    receiverKey: touch.key,
                  ),
                );
                Navigator.pop(dialogContext);
              },
            ),
          ],
        ),
      ],
      DialogDone(leading: _removeAction(dialogContext, ref, touch.key)),
    ],
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: _StepButton.height,
      child: Icon(
        Icons.arrow_forward,
        size: 20,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// A step: *1 · SS · booted*, a raised button with a chevron that says it
/// opens. Rosin when it is a misplay; a clean step is outlined.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.number,
    required this.who,
    required this.verb,
    required this.onTap,
    this.misplay = false,
    this.underline = false,
    super.key,
  });

  /// §15.2: at least 64 px, so the step reads as the control it is.
  static const double height = 64;

  final int number;
  final String who;
  final String verb;
  final bool misplay;

  /// A throw that arrived badly: information, not fault (§15.3).
  final bool underline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fill = misplay
        ? DiamondSemantics.of(context).misplay
        : scheme.surfaceContainerLowest;
    final ink = misplay ? BrandBaseline.onLightFill : scheme.onSurface;
    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandMetrics.radiusMd),
        side: misplay
            ? BorderSide.none
            : BorderSide(color: scheme.onSurface, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          constraints: const BoxConstraints(minWidth: 168),
          padding: const EdgeInsets.only(
            left: BrandMetrics.spaceMd,
            right: BrandMetrics.spaceSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$number',
                style: text.labelMedium?.copyWith(
                  color: ink.withValues(alpha: 0.7),
                  fontFamily: 'JetBrains Mono',
                ),
              ),
              const SizedBox(width: BrandMetrics.spaceSm),
              Text(
                who,
                style: text.titleLarge?.copyWith(
                  color: ink,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: BrandMetrics.spaceSm),
              Text(
                verb,
                style: text.titleMedium?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  decoration: underline ? TextDecoration.underline : null,
                  decorationColor: ink,
                  decorationThickness: 2,
                ),
              ),
              const SizedBox(width: BrandMetrics.spaceXs),
              Icon(Icons.expand_more, size: 20, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ball leads the strip: how it was hit, on Ink. A between-pitch entry
/// has no ball, and reads *Between pitches*.
class _BallStep extends StatelessWidget {
  const _BallStep({
    required this.trajectory,
    required this.battedBall,
    required this.onTap,
  });

  final Trajectory? trajectory;
  final bool battedBall;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.onInverseSurface;
    return Material(
      key: chainBallNodeKey,
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(BrandMetrics.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: _StepButton.height,
          padding: const EdgeInsets.symmetric(horizontal: BrandMetrics.spaceMd),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (battedBall) ...[
                const CustomPaint(size: Size.square(22), painter: _Ball()),
                const SizedBox(width: BrandMetrics.spaceSm),
              ],
              Text(
                battedBall
                    ? (trajectory == null
                          ? 'In play'
                          : trajectoryLabel(trajectory!))
                    : 'Between pitches',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: BrandMetrics.spaceXs),
                Icon(Icons.expand_more, size: 20, color: ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A runner's row under the step that moved her: *Batter safe at 1st*,
/// *R3 scored · unearned · no RBI*. The run's rulings are read here, so the
/// scorer sees them without opening anything (§13.5 v0.77).
class _RunnerRow extends StatelessWidget {
  const _RunnerRow({
    required this.words,
    required this.onTap,
    this.detail,
    this.run = false,
    this.out = false,
    this.rulings,
    super.key,
  });

  final String words;
  final String? detail;
  final bool run;
  final bool out;
  final ScoredRun? rulings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final r = rulings;
    final edited =
        Theme.of(
          context,
        ).outlinedButtonTheme.style?.foregroundColor?.resolve(const {}) ??
        scheme.primary;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandMetrics.radiusSm + 2),
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 168),
          padding: const EdgeInsets.symmetric(
            horizontal: BrandMetrics.spaceMd,
            vertical: BrandMetrics.spaceXs + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                run ? Icons.home_outlined : (out ? Icons.close : Icons.circle),
                size: run || out ? 18 : 10,
                color: scheme.onSurface,
              ),
              const SizedBox(width: BrandMetrics.spaceSm),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    words,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (r != null)
                    Text.rich(
                      TextSpan(
                        style: muted,
                        children: [
                          TextSpan(
                            text:
                                '${r.earned ? 'earned' : 'unearned'} · '
                                '${r.rbi ? 'RBI' : 'no RBI'}',
                          ),
                          if (r.edited)
                            TextSpan(
                              text: ' · your call',
                              style: TextStyle(color: edited),
                            ),
                        ],
                      ),
                    )
                  else if (detail != null)
                    Text(detail!, style: muted),
                ],
              ),
              const SizedBox(width: BrandMetrics.spaceSm),
              Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A baseball, drawn: the bundled fonts have no ⚾ (§15.2 v0.77).
class _Ball extends CustomPainter {
  const _Ball();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    canvas.drawCircle(
      center,
      r - 1,
      Paint()..color = BrandBaseline.onBrandFill,
    );
    final stitch = Paint()
      ..color = BrandBaseline.clay
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final w = size.width;
    canvas
      ..drawPath(
        Path()
          ..moveTo(w * 0.25, w * 0.23)
          ..quadraticBezierTo(w * 0.42, w * 0.5, w * 0.25, w * 0.77),
        stitch,
      )
      ..drawPath(
        Path()
          ..moveTo(w * 0.75, w * 0.23)
          ..quadraticBezierTo(w * 0.58, w * 0.5, w * 0.75, w * 0.77),
        stitch,
      );
  }

  @override
  bool shouldRepaint(_Ball oldDelegate) => false;
}
