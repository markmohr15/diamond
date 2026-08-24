import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/rules/official_scoring.dart'
    show defaultOrdinaryEffort;
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
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
const Key chainReattributeKey = Key('chainReattribute');

/// What a touch node can be retyped to (§15.3's chip menu): the misplay
/// set, plus `deflected` — not a misplay (§13.2 never charges it) but the
/// same kind of correction, so it belongs in the same menu.
const _misplayLabels = <TouchType, String>{
  TouchType.DROPPED: 'Dropped',
  TouchType.BOOTED: 'Booted',
  TouchType.BOBBLED: 'Bobbled',
  TouchType.DEFLECTED: 'Deflected',
  TouchType.WILD_THROW: 'Wild throw',
  TouchType.MISSED_CATCH: 'Missed catch',
  TouchType.TAG_MISSED: 'Tag missed',
};

const _arrivalLabels = <ReceivedQuality, String>{
  ReceivedQuality.SHORT_HOP: 'Short hop',
  ReceivedQuality.HIGH: 'High',
  ReceivedQuality.WIDE: 'Wide',
};

const _howLabels = <How, String>{
  How.FORCE: 'Force',
  How.TAG: 'Tag',
  How.FLY_OUT: 'Fly out',
};

/// Touch types that receive a ball from elsewhere — the ones whose node
/// also offers arrival quality (§15.3).
const _receivingTypes = {
  TouchType.RECEIVED_THROW,
  TouchType.MISSED_CATCH,
  TouchType.DROPPED,
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
            padding: const EdgeInsets.only(left: 16, bottom: 2),
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
          _node(context, scheme, label: '⚾')
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

  /// §15.3's chip menu on a touch node: the misplay set, arrival quality on
  /// receiving nodes, the §13.2 judgment on misplays, and removal.
  void _showTouchSheet(BuildContext context, TouchEntry touch) {
    final controller = ref.read(playDraftProvider.notifier);
    final position = positionAbbreviations[touch.position] ?? touch.position;
    _sheet(context, '$position — what happened?', [
      Wrap(
        spacing: 6,
        children: [
          for (final entry in _misplayLabels.entries)
            ChoiceChip(
              key: chainChipKey(touchTypeValues.reverse[entry.key]!),
              label: Text(entry.value),
              selected: touch.touchType == entry.key,
              onSelected: (_) {
                controller.setTouchType(touch.key, entry.key);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      if (_receivingTypes.contains(touch.touchType)) ...[
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
      if (touch.isMisplay) ...[
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ordinary effort?'),
            const SizedBox(width: 8),
            Switch(
              key: chainChipKey('ordinaryEffort'),
              // Shows what will actually be charged: an unresolved judgment
              // (a wild throw nobody has ruled on) charges nothing, so the
              // switch sits off until someone says she should have had it.
              value:
                  touch.ordinaryEffort ??
                  defaultOrdinaryEffort(touch.touchType) ??
                  false,
              onChanged: (value) {
                controller.setOrdinaryEffort(touch.key, ordinaryEffort: value);
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

  void _showOutSheet(BuildContext context, OutEntry out) {
    final controller = ref.read(playDraftProvider.notifier);
    final who = widget.runnerLabels[out.runnerId] ?? 'Runner';
    _sheet(context, '$who out at ${out.atBase == 4 ? 'home' : out.atBase}', [
      Wrap(
        spacing: 6,
        children: [
          for (final entry in _howLabels.entries)
            ChoiceChip(
              key: chainChipKey(howValues.reverse[entry.key]!),
              label: Text(entry.value),
              selected: out.how == entry.key,
              onSelected: (_) {
                controller.setOutHow(out.key, entry.key);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      ..._ruleCallTiles(context, out.key),
      _removeTile(context, out.key),
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
