/// §15.5 v0.77, board 16D: the review card at the ✓.
///
/// It opens only when the play leaves a question open — §13.2's reach, the
/// sacrifice (§13.6) — and asks them together, instead of one dialog after
/// another. Each run's earned and RBI rulings are on it because they are on
/// the same play, but they never open it (Mark, 2026-11-25).
///
/// Nothing is written until *Commit play*. The answers are held here and
/// applied to a copy of the draft, so the sentences and the rulings on the
/// card read as the play will be saved, and changing an answer is just
/// tapping another one. *Back to the field* leaves the draft as it was.
library;

import 'dart:async';

import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/play/play_preview.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/ui/dialog/dialog_parts.dart';
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/field_canvas/play_stream.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Keys the widget tests resolve against.
@visibleForTesting
const Key reviewCommitKey = Key('reviewCommit');
@visibleForTesting
const Key reviewBackKey = Key('reviewBack');
@visibleForTesting
Key reviewRunKey(int legKey, String answer) => Key('reviewRun-$legKey-$answer');

/// One answer to the batter's reach, as the draft transform it makes.
typedef ReachAnswer = ({
  String id,
  String label,
  bool misplay,
  PlayDraft Function(PlayDraft) apply,
});

/// Opens the card. [reach] is the reach question's answers, or null when it
/// is not open; [sacrificeLabel] names the sacrifice question for this play
/// (*Sacrifice fly?*). [sacrificeKey] and [reachKey] key the answers the way
/// the dialogs they replace were keyed; [runnerName] names a run's runner.
Future<void> showReviewCard(
  BuildContext context, {
  required String Function(String runnerId) runnerName,
  required String sacrificeLabel,
  required Key Function(String answer) sacrificeKey,
  required Key Function(String id) reachKey,
  List<ReachAnswer>? reach,
}) {
  return showFieldDialog<void>(
    context,
    title: 'Check the play',
    question: 'Nothing is saved until you commit it.',
    children: (_) => [
      _ReviewBody(
        reach: reach,
        runnerName: runnerName,
        sacrificeLabel: sacrificeLabel,
        sacrificeKey: sacrificeKey,
        reachKey: reachKey,
      ),
    ],
  );
}

class _ReviewBody extends ConsumerStatefulWidget {
  const _ReviewBody({
    required this.reach,
    required this.runnerName,
    required this.sacrificeLabel,
    required this.sacrificeKey,
    required this.reachKey,
  });

  final List<ReachAnswer>? reach;
  final String Function(String runnerId) runnerName;
  final String sacrificeLabel;
  final Key Function(String answer) sacrificeKey;
  final Key Function(String id) reachKey;

  @override
  ConsumerState<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends ConsumerState<_ReviewBody> {
  String? _reachId;
  bool? _sacrifice;
  final _rulings = <int, RunRuling>{};

  /// The draft the card would commit: the field's, with every answer given
  /// here applied. Read fresh each build, so it can never drift from what
  /// the field holds.
  PlayDraft _answered(PlayDraft draft) {
    var next = draft;
    final reach = widget.reach;
    if (reach != null) {
      final chosen = reach.where((a) => a.id == _reachId).firstOrNull;
      if (chosen != null) next = chosen.apply(next);
    }
    if (_sacrifice != null) next = next.copyWith(sacrifice: _sacrifice);
    for (final MapEntry(:key, :value) in _rulings.entries) {
      next = next.withRunRuling(key, value);
    }
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(playDraftProvider).valueOrNull;
    final visible = ref.watch(visibleStreamProvider).valueOrNull;
    final fold = ref.watch(gameControllerProvider).valueOrNull;
    if (draft == null || visible == null || fold == null) {
      return const SizedBox.shrink();
    }
    final answered = _answered(draft);
    final text = Theme.of(context).textTheme;

    final reach = widget.reach;
    final asksSacrifice = answered.invitesSacrifice(outs: fold.outs);
    final complete =
        (reach == null || _reachId != null) &&
        (!asksSacrifice || _sacrifice != null);
    final sentence = previewPlayLine(
      visible,
      answered,
      before: fold.bases,
      outs: fold.outs,
      evenIfAsking: true,
    );
    final runs = previewRuns(visible, answered, before: fold.bases);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sentence != null) ...[
          const DialogSection('What happened'),
          Text(sentence, style: text.bodyLarge),
        ],
        if (reach != null) ...[
          const DialogSection('Batter safe at 1st — how?'),
          AnswerGrid(
            children: [
              for (final answer in reach)
                AnswerButton(
                  key: widget.reachKey(answer.id),
                  label: answer.label,
                  selected: _reachId == answer.id,
                  tone: answer.misplay ? AnswerTone.misplay : AnswerTone.ink,
                  onPressed: () => setState(() => _reachId = answer.id),
                ),
            ],
          ),
        ],
        if (asksSacrifice) ...[
          DialogSection(widget.sacrificeLabel),
          AnswerGrid(
            children: [
              AnswerButton(
                key: widget.sacrificeKey('yes'),
                label: 'Yes',
                selected: _sacrifice ?? false,
                onPressed: () => setState(() => _sacrifice = true),
              ),
              AnswerButton(
                key: widget.sacrificeKey('no'),
                label: 'No',
                selected: _sacrifice == false,
                onPressed: () => setState(() => _sacrifice = false),
              ),
            ],
          ),
        ],
        for (final MapEntry(key: legKey, value: run) in runs.entries) ...[
          DialogSection(
            '${widget.runnerName(run.runnerId)} scored: earned, and an RBI?',
          ),
          RunRulingsAnswers(
            run: run,
            keyOf: (answer) => reviewRunKey(legKey, answer),
            onChanged: (ruling) => setState(() => _rulings[legKey] = ruling),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: BrandMetrics.spaceLg),
          child: Row(
            children: [
              QuietAction(
                key: reviewBackKey,
                icon: Icons.arrow_back,
                label: 'Back to the field',
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
              // Hidden, not disabled (§23.1), and its space kept: it
              // appears once every open question has an answer.
              Visibility(
                visible: complete,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: FilledButton.icon(
                  key: reviewCommitKey,
                  onPressed: complete
                      ? () {
                          Navigator.pop(context);
                          unawaited(_commit(answered));
                        }
                      : null,
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

  /// The card's answers as one step, so Back one takes them back together,
  /// then the ✓.
  Future<void> _commit(PlayDraft answered) async {
    final controller = ref.read(playDraftProvider.notifier);
    await controller.applyAnswers(answered);
    await controller.commit();
  }
}

/// A run's two rulings, Diamond's call beside the scorer's (§13.5 v0.77,
/// §23.7) — on the run's menu and on the review card alike.
///
/// The answer that agrees with the derivation is stored as nothing, so
/// choosing Diamond's answer *is* taking the override back, and the draft
/// never holds a ruling that restates the projection.
class RunRulingsAnswers extends StatelessWidget {
  const RunRulingsAnswers({
    required this.run,
    required this.keyOf,
    required this.onChanged,
    super.key,
  });

  final ScoredRun run;

  /// The key for each answer: `earned`, `unearned`, `rbi`, `no_rbi`,
  /// `use_diamonds_call`.
  final Key Function(String answer) keyOf;
  final ValueChanged<RunRuling> onChanged;

  @override
  Widget build(BuildContext context) {
    RunRuling ruling({bool? earned, bool? rbi}) {
      final e = earned ?? run.earned;
      final r = rbi ?? run.rbi;
      return RunRuling(
        earned: e == run.derivedEarned ? null : e,
        rbi: r == run.derivedRbi ? null : r,
      );
    }

    Widget answer(
      String id,
      String label, {
      required bool value,
      required bool current,
      required bool derived,
      required RunRuling Function() choose,
    }) {
      final selected = current == value;
      return AnswerButton(
        key: keyOf(id),
        label: label,
        selected: selected,
        tone: derived == value ? AnswerTone.ink : AnswerTone.yours,
        tag: derived == value
            ? CallTag.diamond
            : (selected ? CallTag.yours : null),
        onPressed: () => onChanged(choose()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnswerGrid(
          children: [
            answer(
              'earned',
              'Earned',
              value: true,
              current: run.earned,
              derived: run.derivedEarned,
              choose: () => ruling(earned: true),
            ),
            answer(
              'unearned',
              'Unearned',
              value: false,
              current: run.earned,
              derived: run.derivedEarned,
              choose: () => ruling(earned: false),
            ),
          ],
        ),
        const SizedBox(height: BrandMetrics.spaceSm),
        AnswerGrid(
          children: [
            answer(
              'rbi',
              'RBI',
              value: true,
              current: run.rbi,
              derived: run.derivedRbi,
              choose: () => ruling(rbi: true),
            ),
            answer(
              'no_rbi',
              'No RBI',
              value: false,
              current: run.rbi,
              derived: run.derivedRbi,
              choose: () => ruling(rbi: false),
            ),
          ],
        ),
        if (run.edited)
          Align(
            alignment: Alignment.centerLeft,
            child: QuietAction(
              key: keyOf('use_diamonds_call'),
              label: "Use Diamond's call",
              accent: true,
              onPressed: () => onChanged(const RunRuling()),
            ),
          ),
      ],
    );
  }
}
