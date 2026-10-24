import 'dart:async';

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/play/possible_entries.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
@visibleForTesting
const Key chainReattributeKey = Key('chainReattribute');

/// Labels for what a touch node can be retyped to (§15.3's chip menu). Which
/// of them a node offers is [retypeChoices]'s call, not this map's.
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
  ReceivedQuality.SHORT_HOP: 'Short hop',
  ReceivedQuality.HIGH: 'High',
  ReceivedQuality.WIDE: 'Wide',
};

/// Labels for an out's `how` that [possibleHows] never offers as a choice
/// but an out can already carry — set by the ⚖ or by its own path — so the
/// sheet can still show what she is out on.
const _otherHowLabels = <How, String>{
  How.INTERFERENCE: 'Interference',
  How.BATTED_BALL_CONTACT: 'Struck by batted ball',
};

/// §15.2's play chain strip: the play as nodes — ⚾ → 6 → 4 → 3 — with
/// runner consequences hanging beneath the entry that caused them, every
/// node a live control. Misplays render amber (§15.3: fault not yet
/// adjudicated); non-clean arrivals get an underline, not amber — they're
/// information, not fault.
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
  /// §13.4's two-tap re-attribution: the leg waiting for its enabler. While
  /// set, tapping a touch node re-attributes instead of opening its sheet.
  int? _reattributingLegKey;

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final semantics = DiamondSemantics.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Columns: ⚾ first, then each touch/rule-call in entry order.
    // Consequences hang beneath their enabler (legs) / putout credit
    // (outs); unattributed ones hang beneath ⚾.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_reattributingLegKey != null)
          Padding(
            padding: const EdgeInsets.only(
              left: BrandMetrics.spaceLg,
              bottom: 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tap the touch that enabled it',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                IconButton(
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _reattributingLegKey = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final head in heads) ...[
                _column(
                  context,
                  draft,
                  head,
                  consequencesByHead[head] ?? [],
                  semantics,
                  scheme,
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _column(
    BuildContext context,
    PlayDraft draft,
    int? headKey,
    List<PlayEntry> consequences,
    DiamondSemantics semantics,
    ColorScheme scheme,
  ) {
    final head = headKey == null ? null : draft.entryByKey(headKey);
    return Column(
      children: [
        if (head == null)
          _node(
            context,
            scheme,
            key: chainBallNodeKey,
            label: '⚾',
            onTap: _offersInfieldFly(draft)
                ? () => _showBallNodeSheet(context)
                : null,
          )
        else if (head is TouchEntry)
          _touchNode(context, head, semantics, scheme)
        else
          _node(
            context,
            scheme,
            key: chainNodeKey(head.key),
            label: '⚖',
            onTap: () => _showRuleCallNodeSheet(context, head.key),
          ),
        for (final consequence in consequences)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _consequenceChip(context, consequence, scheme),
          ),
      ],
    );
  }

  Widget _touchNode(
    BuildContext context,
    TouchEntry touch,
    DiamondSemantics semantics,
    ColorScheme scheme,
  ) {
    final reattributing = _reattributingLegKey != null;
    return _node(
      context,
      scheme,
      key: chainNodeKey(touch.key),
      label: positionAbbreviations[touch.position] ?? '${touch.position}',
      fill: touch.isMisplay ? semantics.misplay : null,
      underline:
          touch.receivedQuality != null &&
          touch.receivedQuality != ReceivedQuality.CLEAN,
      outlined: reattributing,
      onTap: () {
        final legKey = _reattributingLegKey;
        if (legKey != null) {
          ref
              .read(playDraftProvider.notifier)
              .reattributeLeg(legKey, touch.key);
          setState(() => _reattributingLegKey = null);
          return;
        }
        _showTouchSheet(context, touch);
      },
    );
  }

  Widget _node(
    BuildContext context,
    ColorScheme scheme, {
    required String label,
    Key? key,
    Color? fill,
    bool underline = false,
    bool outlined = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill ?? scheme.surfaceContainerHigh,
          border: outlined ? Border.all(color: scheme.primary, width: 2) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            if (underline)
              Container(width: 14, height: 2, color: scheme.onSurface),
          ],
        ),
      ),
    );
  }

  Widget _consequenceChip(
    BuildContext context,
    PlayEntry entry,
    ColorScheme scheme,
  ) {
    final (label, onTap) = switch (entry) {
      LegEntry() => (
        '${widget.runnerLabels[entry.runnerId] ?? '?'}'
            '→${entry.to == 4 ? '⌂' : entry.to}',
        () => _showLegSheet(context, entry),
      ),
      OutEntry() => (
        '${widget.runnerLabels[entry.runnerId] ?? '?'}'
            '✕${entry.atBase == 4 ? '⌂' : entry.atBase}',
        () => _showOutSheet(context, entry),
      ),
      _ => ('?', () {}),
    };
    return InkWell(
      key: chainNodeKey(entry.key),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: scheme.surfaceContainerHigh,
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }

  /// Whether this node should ask **how the throw arrived**: only a
  /// reception, which [throwerInto] decides on provenance rather than type.
  /// `dropped` describes muffing a throw *or* a ball off the bat, so
  /// dropping a routine fly used to ask how the throw arrived, for a ball
  /// nobody threw.
  bool _offersArrivalQuality(TouchEntry touch) =>
      throwerInto(widget.draft, touch) != null;

  /// §15.3's chip menu on a touch node: the misplay set, arrival quality on
  /// receiving nodes, the §13.2 judgment on misplays, and removal.
  void _showTouchSheet(BuildContext context, TouchEntry touch) {
    final controller = ref.read(playDraftProvider.notifier);
    final position = positionAbbreviations[touch.position] ?? touch.position;
    _sheet(context, '$position — what happened?', [
      Wrap(
        spacing: 6,
        children: [
          // Retyping is another way in to the popup's vocabulary, so it
          // offers only what the popup could have — a catcher chasing a
          // pitch cannot be retyped to *Booted* any more than she could be
          // entered that way (DIA-019 H).
          for (final type in retypeChoices(widget.draft, touch))
            ChoiceChip(
              key: chainChipKey(touchTypeValues.reverse[type]!),
              label: Text(_misplayLabels[type]!),
              selected: touch.touchType == type,
              onSelected: (_) {
                controller.setTouchType(touch.key, type);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      // §13.2: `wild_throw` on a node means *this fielder threw it away*, and
      // the grammar is right — but the throw **arrives** badly, and the
      // receiver's node is the one that just appeared, so that is where the
      // finger goes. Confirmed in the field: a catcher's throw to first
      // recorded `wild_throw` on position 3, which charges E3 instead of E2.
      //
      // So the receiving node offers the question in the direction the scorer
      // is actually looking, and it retypes the *thrower*.
      if (throwerInto(widget.draft, touch) case final thrower?) ...[
        const SizedBox(height: 8),
        ActionChip(
          key: chainChipKey('throw_was_wild'),
          label: const Text('The throw was wild'),
          onPressed: () {
            controller.markThrowWild(
              throwerKey: thrower.key,
              receiverKey: touch.key,
            );
            Navigator.pop(context);
          },
        ),
      ],
      if (_offersArrivalQuality(touch)) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final entry in _arrivalLabels.entries)
              ChoiceChip(
                key: chainChipKey(receivedQualityValues.reverse[entry.key]!),
                label: Text(entry.value),
                selected: touch.receivedQuality == entry.key,
                onSelected: (_) {
                  controller.setReceivedQuality(touch.key, entry.key);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ],
      _removeTile(context, touch.key),
    ]);
  }

  void _showLegSheet(BuildContext context, LegEntry leg) {
    final who = widget.runnerLabels[leg.runnerId] ?? 'Runner';
    _sheet(context, '$who to ${leg.to == 4 ? 'home' : leg.to} — why?', [
      ListTile(
        key: chainReattributeKey,
        leading: const Icon(Icons.link),
        title: const Text('Re-attribute — tap the enabling touch'),
        onTap: () {
          Navigator.pop(context);
          setState(() => _reattributingLegKey = leg.key);
        },
      ),
      ..._ruleCallTiles(context, leg.key),
      _removeTile(context, leg.key),
    ]);
  }

  /// An out's sheet offers the same outs the OUT dialog did (§4.3) — a
  /// between-pitch out is never a force, and neither is a runner's out
  /// after a catch (DIA-019 H). Only outs entered before this one count
  /// against her force; see [possibleHows]. Her current `how` always shows.
  void _showOutSheet(BuildContext context, OutEntry out) {
    final controller = ref.read(playDraftProvider.notifier);
    final who = widget.runnerLabels[out.runnerId] ?? 'Runner';
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
    _sheet(context, '$who out at ${out.atBase == 4 ? 'home' : out.atBase}', [
      Wrap(
        spacing: 6,
        children: [
          for (final (label, how) in hows)
            ChoiceChip(
              key: chainChipKey(howValues.reverse[how]!),
              label: Text(label),
              selected: out.how == how,
              onSelected: (_) {
                controller.setOutHow(out.key, how);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      ..._ruleCallTiles(context, out.key),
      _removeTile(context, out.key),
    ]);
  }

  /// The ball's landing node is live only while it has something to offer
  /// — today that is the infield fly alone (§15.3), so a node that cannot
  /// say one is not a control.
  bool _offersInfieldFly(PlayDraft draft) {
    final game = ref.watch(gameControllerProvider).valueOrNull;
    if (game == null) return false;
    return offersInfieldFly(draft, outs: game.outs, bases: game.bases);
  }

  /// §15.3's menu on the ball's landing node. Kept findable rather than
  /// asked: an infield fly is rare, and its value is what it turns off —
  /// every force, and the walk-up that presumed the batter was running.
  void _showBallNodeSheet(BuildContext context) {
    _sheet(context, 'Ball in play', [
      ListTile(
        key: chainChipKey('infield_fly'),
        leading: const Icon(Icons.balance),
        title: const Text('Infield fly'),
        onTap: () {
          Navigator.pop(context);
          unawaited(ref.read(playDraftProvider.notifier).declareInfieldFly());
        },
      ),
    ]);
  }

  void _showRuleCallNodeSheet(BuildContext context, int key) {
    _sheet(context, 'Rule call', [_removeTile(context, key)]);
  }

  /// §15.3 v0.43: the ⚖ calls are baserunning facts, so they live on the
  /// runner-consequence sheets — attached to this movement, inserted into
  /// the chain just before it — never on a standing button.
  List<Widget> _ruleCallTiles(BuildContext context, int consequenceKey) {
    final controller = ref.read(playDraftProvider.notifier);
    return [
      for (final callType in const [
        CallType.OBSTRUCTION,
        CallType.INTERFERENCE_RUNNER,
      ])
        ListTile(
          key: chainChipKey(callTypeValues.reverse[callType]!),
          leading: const Icon(Icons.balance),
          title: Text(
            callType == CallType.OBSTRUCTION
                ? 'Obstruction'
                : 'Interference (runner)',
          ),
          onTap: () async {
            Navigator.pop(context);
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
    ];
  }

  Widget _removeTile(BuildContext context, int key) {
    return ListTile(
      key: chainRemoveKey,
      leading: const Icon(Icons.delete_outline),
      title: const Text('Remove'),
      onTap: () {
        ref.read(playDraftProvider.notifier).removeEntry(key);
        Navigator.pop(context);
      },
    );
  }

  /// Every node menu: a centered dialog, only as big as its content —
  /// front and center, matching the surface's other popups (see
  /// [showFieldDialog] for the sizing they share).
  void _sheet(BuildContext context, String title, List<Widget> children) {
    showFieldDialog<void>(
      context,
      title: title,
      alignment: CrossAxisAlignment.start,
      children: (_) => children,
    );
  }
}
