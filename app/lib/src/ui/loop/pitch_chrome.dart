import 'dart:math' as math;

import 'package:diamond/src/call/canonical_cells.dart';
import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
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
const Key batsRightKey = Key('batsRight');
@visibleForTesting
const Key batsLeftKey = Key('batsLeft');
@visibleForTesting
const Key openIdleFieldKey = Key('openIdleField');
@visibleForTesting
const Key themeLightKey = Key('themeLight');
@visibleForTesting
const Key themeDarkKey = Key('themeDark');
@visibleForTesting
const Key railCallKey = Key('railCall');
@visibleForTesting
const Key railRecordKey = Key('railRecord');
@visibleForTesting
const Key railStatusKey = Key('railStatus');

/// A canonical cell in words, from the batter's point of view: *Low away*,
/// *Up in*, *Middle*. The ring cells read *Below*, *High*, *Off in* and
/// *Off away*, so a pitch off the plate never reads as a strike.
String describeCell(CanonicalCell cell) {
  const rows = ['Below', 'Low', 'Middle', 'Up', 'High'];
  const columns = ['off in', 'in', 'middle', 'away', 'off away'];
  if (cell.row == 2 && cell.column == 2) return 'Middle';
  return '${rows[cell.row]} ${columns[cell.column]}';
}

/// The call in words for the rail's first stop: *Drop · Low middle · 702*.
///
/// A zone of one cell is named by the cell, because the fine layout's zone
/// labels are its cell ids; a grouped zone (*Bury*, *Off In*) keeps its
/// coach-given label.
String describeCall(TeamCallConfig config, CallIntent intent) {
  final type = config.arsenal
      .where((t) => t.id == intent.pitchTypeId)
      .map((t) => t.name)
      .firstOrNull;
  final zone = config.layout.byId(intent.zoneId);
  final where = zone == null
      ? intent.zoneId
      : zone.cells.length == 1
      ? describeCell(zone.cells.single)
      : zone.label;
  return [type ?? intent.pitchTypeId, where, ?intent.code].join(' · ');
}

/// Where the pitch went, in words, for the rail's second stop. [actual] is
/// absolute (§3.1), so it is turned to the batter's frame before it is
/// named — *in* is inside to whoever is batting.
String describeLocation({
  required ZoneCoord? actual,
  required BounceCoord? bounce,
  required BatterSide side,
}) {
  if (bounce != null) return 'In the dirt';
  if (actual == null) return 'No location';
  return describeCell(cellContaining(relativeToBatter(actual, side)));
}

/// 15A's batter strip, between the top bar and the rail: which box she is
/// in, who is on, the way to the between-pitch field, and the theme.
///
/// [showBats] is false while backfilling a pitch already written, whose side
/// is on the event — a flip there would describe nobody. [onField] is null
/// off the call screen: the idle field opens between pitches, not during
/// one (§11.1).
class BatterStrip extends ConsumerWidget {
  const BatterStrip({required this.showBats, this.onField, super.key});

  final bool showBats;
  final VoidCallback? onField;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final side = ref.watch(batterSideProvider);
    final batter = ref.watch(dueBatterProvider);
    final bases =
        ref.watch(gameControllerProvider).valueOrNull?.bases ?? BaseState.empty;
    final dark = ref.watch(themeModeProvider).valueOrNull == ThemeMode.dark;

    void chooseSide(BatterSide chosen) {
      if (batter == null) return;
      ref.read(batterSideChoiceProvider.notifier).state = (
        batterId: batter,
        side: chosen,
      );
    }

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: BrandMetrics.spaceLg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (showBats) ...[
            Text(
              'BATS',
              style: BrandType.eyebrow.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: BrandMetrics.spaceMd),
            _Segmented(
              options: [
                (
                  key: batsRightKey,
                  label: 'Right',
                  selected: side == BatterSide.R,
                  onTap: () => chooseSide(BatterSide.R),
                ),
                (
                  key: batsLeftKey,
                  label: 'Left',
                  selected: side == BatterSide.L,
                  onTap: () => chooseSide(BatterSide.L),
                ),
              ],
            ),
            const SizedBox(width: BrandMetrics.spaceLg),
          ],
          _BaseDiamond(bases: bases),
          const SizedBox(width: BrandMetrics.spaceLg),
          if (onField == null) const Spacer(),
          if (onField case final open?) ...[
            // The caption gives way first on a narrow tablet; FIELD stays.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: openIdleFieldKey,
                  onPressed: open,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandMetrics.spaceMd,
                    ),
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.onSurface, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('FIELD', style: BrandType.eyebrow),
                      const SizedBox(width: BrandMetrics.spaceSm),
                      Flexible(
                        child: Text(
                          'steals, WP/PB',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 32,
              margin: const EdgeInsets.symmetric(
                horizontal: BrandMetrics.spaceMd,
              ),
              color: scheme.outline,
            ),
          ],
          // Manual, default light, never the system's (DIA-021): the field's
          // lighting is what matters at a night game, not the device clock.
          _Segmented(
            mono: true,
            options: [
              (
                key: themeLightKey,
                label: 'LIGHT',
                selected: !dark,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .choose(ThemeMode.light),
              ),
              (
                key: themeDarkKey,
                label: 'DARK',
                selected: dark,
                onTap: () =>
                    ref.read(themeModeProvider.notifier).choose(ThemeMode.dark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

typedef _SegmentOption = ({
  Key key,
  String label,
  bool selected,
  VoidCallback onTap,
});

/// Two labeled segments, the chosen one filled with ink. Value, not hue, so
/// it reads in glare and in grayscale, and it spends no accent (§23.1.2).
class _Segmented extends StatelessWidget {
  const _Segmented({required this.options, this.mono = false});

  final List<_SegmentOption> options;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(BrandMetrics.radiusMd);
    // The outline is a *foreground*: drawn under the segments, their fills
    // painted over it and the chosen side lost its edge entirely.
    return Container(
      height: 44,
      decoration: BoxDecoration(borderRadius: radius),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: scheme.onSurface, width: 1.5),
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, option) in options.indexed) ...[
            if (i > 0) Container(width: 1.5, color: scheme.onSurface),
            Semantics(
              selected: option.selected,
              button: true,
              child: InkWell(
                key: option.key,
                onTap: option.onTap,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: BrandMetrics.spaceLg,
                  ),
                  color: option.selected ? scheme.onSurface : scheme.surface,
                  child: Text(
                    option.label,
                    style: (mono ? BrandType.eyebrow : const TextStyle())
                        .copyWith(
                          fontWeight: FontWeight.w700,
                          color: option.selected
                              ? scheme.surface
                              : scheme.onSurface,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Who is on, as three bases: filled is occupied.
class _BaseDiamond extends StatelessWidget {
  const _BaseDiamond({required this.bases});

  final BaseState bases;

  @override
  Widget build(BuildContext context) {
    final occupied = [
      bases.first != null,
      bases.second != null,
      bases.third != null,
    ];
    final names = ['first', 'second', 'third'];
    final on = [
      for (var i = 0; i < 3; i++)
        if (occupied[i]) names[i],
    ];
    return Semantics(
      label: on.isEmpty ? 'Bases empty' : 'Runners on ${on.join(', ')}',
      child: CustomPaint(
        size: const Size.square(44),
        painter: _BaseDiamondPainter(
          occupied: occupied,
          ink: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _BaseDiamondPainter extends CustomPainter {
  _BaseDiamondPainter({required this.occupied, required this.ink});

  final List<bool> occupied;
  final Color ink;

  /// A base's side, and the distance between neighboring bases' centers.
  /// Spaced so each pair keeps a gap: half a side reaches toward each
  /// neighbor, so the spacing must beat a full side. 15A's own numbers
  /// (12 on 9.9) overlapped, and the bases read as one shape.
  static const double _side = 11;
  static const double _spacing = 15;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 44;
    const d = _spacing / math.sqrt2;
    // Centered on the group's own extent, which runs from second's top
    // corner to first and third's bottom corners.
    final cx = 22 * s;
    final cy = (22 + d / 2) * s;
    final centers = [
      Offset(cx + d * s, cy), // first, on the right
      Offset(cx, cy - d * s), // second, on top
      Offset(cx - d * s, cy), // third
    ];
    for (var i = 0; i < 3; i++) {
      canvas
        ..save()
        ..translate(centers[i].dx, centers[i].dy)
        ..rotate(math.pi / 4);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: _side * s,
        height: _side * s,
      );
      // The same ink and weight as the strip's control borders, so an empty
      // base and an occupied one read as one set.
      canvas
        ..drawRect(
          rect,
          occupied[i]
              ? (Paint()..color = ink)
              : (Paint()
                  ..color = ink
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.5 * s),
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_BaseDiamondPainter old) =>
      old.ink != ink || !_sameList(old.occupied, occupied);

  static bool _sameList(List<bool> a, List<bool> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
}

/// 15A's rail: the pitch's two stops and where you are (DIA-021c).
///
/// **1 CALL** is where the pitch starts, and once the ✓ freezes it, it
/// echoes the call; tapped from the location step it goes back to the
/// pending call. **2 RECORD** is live from the start — *Jump here — no
/// call* drops the call and opens the zone for a pitch nobody called, which
/// is what replaced *Skip call* — and once located it says where.
class PitchRail extends ConsumerWidget {
  const PitchRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final flow = ref.watch(pitchFlowProvider);
    final controller = ref.read(pitchFlowProvider.notifier);
    final config = ref.watch(teamCallConfigProvider);
    final side = ref.watch(batterSideProvider);
    final gs = ref.watch(gameControllerProvider).valueOrNull;

    final intent = flow.intent;
    final calling = flow.step == PitchStep.call;
    final located = flow.step == PitchStep.outcome;

    final call = calling
        ? const _RailStop(
            key: railCallKey,
            number: '1 CALL',
            text: 'Yell it, then ✓',
            state: _StopState.current,
          )
        : _RailStop(
            key: railCallKey,
            number: '1 CALL',
            text: intent == null ? 'No call' : describeCall(config, intent),
            state: _StopState.done,
            checked: intent != null,
            onTap: flow.step == PitchStep.actual ? controller.backToCall : null,
          );

    final record = switch (flow.step) {
      PitchStep.call => _RailStop(
        key: railRecordKey,
        number: '2 RECORD',
        text: 'Jump here — no call',
        state: _StopState.live,
        onTap: controller.skipCall,
      ),
      _ when located => _RailStop(
        key: railRecordKey,
        number: '2 RECORD',
        text: describeLocation(
          actual: flow.actual,
          bounce: flow.bounce,
          side: side,
        ),
        state: _StopState.done,
        checked: flow.actual != null || flow.bounce != null,
      ),
      _ => const _RailStop(
        key: railRecordKey,
        number: '2 RECORD',
        text: 'Where it crossed',
        state: _StopState.current,
      ),
    };

    final where = switch (flow.step) {
      PitchStep.call => 'CALL',
      PitchStep.actual => 'RECORD',
      _ => 'RESULT',
    };
    final number = (gs?.pitchesThisPlateAppearance ?? 0) + 1;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: BrandMetrics.spaceLg),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Flexible(child: call),
          Container(
            width: 18,
            height: 2,
            margin: const EdgeInsets.symmetric(
              horizontal: BrandMetrics.spaceSm,
            ),
            color: scheme.outline,
          ),
          Flexible(child: record),
          const SizedBox(width: BrandMetrics.spaceLg),
          Text(
            'PITCH $number · $where',
            key: railStatusKey,
            style: BrandType.eyebrow.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// [current] is where you are; [live] is a stop you can jump to; [done] is
/// behind you, filled with ink like 13A's.
enum _StopState { current, live, done }

class _RailStop extends StatelessWidget {
  const _RailStop({
    required this.number,
    required this.text,
    required this.state,
    this.checked = false,
    this.onTap,
    super.key,
  });

  final String number;
  final String text;
  final _StopState state;
  final bool checked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grassLine = DiamondSemantics.of(context).grassLine;
    final done = state == _StopState.done;
    final foreground = done ? scheme.surface : scheme.onSurface;
    final muted = done
        ? scheme.surface.withValues(alpha: 0.72)
        : scheme.onSurfaceVariant;
    final border = switch (state) {
      // Grass as line marks where you are (15A). Brand tier, not the team
      // accent: an accent is a fill, and a dark one vanishes as a line on
      // the dark theme (§23.3).
      _StopState.current => Border.all(color: grassLine, width: 2),
      _StopState.live => Border.all(color: scheme.onSurface, width: 1.5),
      _StopState.done => null,
    };

    final body = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: BrandMetrics.spaceMd),
      decoration: BoxDecoration(
        color: done ? scheme.onSurface : scheme.surfaceContainerLowest,
        border: border,
        borderRadius: BorderRadius.circular(BrandMetrics.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            number,
            style: BrandType.eyebrow.copyWith(
              color: state == _StopState.current ? grassLine : muted,
            ),
          ),
          const SizedBox(width: BrandMetrics.spaceSm),
          Flexible(
            child: Text.rich(
              withCheckIcons(
                text,
                TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (checked) ...[
            const SizedBox(width: BrandMetrics.spaceSm),
            Icon(Icons.check, size: 18, color: muted),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BrandMetrics.radiusSm),
        child: body,
      ),
    );
  }
}
