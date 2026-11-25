/// §23.7 (v0.77): the parts every dialog in the app is built from — board
/// 16E. A dialog's frame is `showFieldDialog`; what goes inside it is these.
///
/// - Every answer is an [AnswerButton] at least 56 px tall, laid out by
///   [AnswerGrid]. No list tiles, no chips.
/// - What is recorded now is **selected**: solid Ink, or Rosin when the answer
///   is a misplay (§23.2). Never a grey check.
/// - Rarer answers sit under a [DialogSection] label in the same dialog,
///   never behind a second tap.
/// - A ruling Diamond derived carries [CallTag.diamond]; the scorer's own
///   answer is solid accent with [CallTag.yours] — the one datum she put
///   there, so the one that carries the accent (§23.1).
/// - A removal is a [QuietAction], apart from the answers; the dialog
///   closes with [DialogDone] or the one action it exists for.
library;

import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/brand_type.dart';
import 'package:diamond/src/ui/theme/diamond_semantics.dart';
import 'package:material_ui/material_ui.dart';

/// How a selected [AnswerButton] is filled.
enum AnswerTone {
  /// Solid Ink: what is recorded now.
  ink,

  /// Rosin: a misplay, the same amber the step wears on the strip (§23.2).
  misplay,

  /// The accent: the scorer's own answer to a ruling Diamond derived.
  yours,
}

/// The small label under an answer that says whose ruling it is (§23.7).
enum CallTag {
  /// Diamond derived this answer.
  diamond("DIAMOND'S CALL"),

  /// The scorer overrode Diamond with this answer.
  yours('YOUR CALL');

  const CallTag(this.label);

  /// Upper case already: [BrandType.eyebrow] is wrong on lowercase.
  final String label;
}

/// One answer in a dialog: a 56 px button that reads as selected when it is
/// what is recorded now.
class AnswerButton extends StatelessWidget {
  const AnswerButton({
    required this.label,
    required this.onPressed,
    this.detail,
    this.selected = false,
    this.tone = AnswerTone.ink,
    this.tag,
    this.primary = false,
    super.key,
  });

  final String label;

  /// A second, smaller line: what the answer does, when the label alone
  /// can't say it (*not an error, the ball kept going*).
  final String? detail;

  final bool selected;
  final AnswerTone tone;
  final CallTag? tag;

  /// The one action the dialog exists for (*Discard play*, *Took third*):
  /// solid Ink like a selected answer, because it is the answer the dialog
  /// leads with — 14B draws it so. Not a selection: nothing is recorded yet.
  final bool primary;
  final VoidCallback onPressed;

  /// §23.7's floor. Above the theme's 40 px touch target on purpose: these
  /// are the answers a scorer taps mid-play, standing up.
  static const double minHeight = 56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantics = DiamondSemantics.of(context);
    final (Color fill, Color ink, Color border) = !(selected || primary)
        ? (scheme.surfaceContainerHigh, scheme.onSurface, scheme.outline)
        : switch (tone) {
            AnswerTone.ink => (
              scheme.inverseSurface,
              scheme.onInverseSurface,
              scheme.inverseSurface,
            ),
            // Rosin is light in both themes, so its ink is always dark.
            AnswerTone.misplay => (
              semantics.misplay,
              BrandBaseline.onLightFill,
              semantics.misplay,
            ),
            AnswerTone.yours => (
              scheme.primary,
              scheme.onPrimary,
              scheme.primary,
            ),
          };
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandMetrics.radiusMd),
          side: BorderSide(color: border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BrandMetrics.spaceMd,
                vertical: BrandMetrics.spaceSm,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: ink.withValues(alpha: 0.8),
                      ),
                    ),
                  if (tag != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        tag!.label,
                        style: BrandType.eyebrow.copyWith(
                          fontSize: 10,
                          letterSpacing: 10 * 0.1,
                          color: ink.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Answers in rows of [columns], each the same width — 14B's grid. An odd
/// last answer takes the whole row rather than leaving a hole.
class AnswerGrid extends StatelessWidget {
  const AnswerGrid({required this.children, this.columns = 2, super.key});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <List<Widget>>[
      for (var i = 0; i < children.length; i += columns)
        children.sublist(
          i,
          i + columns > children.length ? children.length : i + columns,
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const SizedBox(height: BrandMetrics.spaceSm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, answer) in row.indexed) ...[
                  if (i > 0) const SizedBox(width: BrandMetrics.spaceSm),
                  Expanded(child: answer),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A small mono label over the rarer answers in the same dialog (§23.7).
class DialogSection extends StatelessWidget {
  const DialogSection(this.label, {super.key});

  /// Upper-cased here: [BrandType.eyebrow] is wrong on lowercase.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: BrandMetrics.spaceMd,
        bottom: BrandMetrics.spaceSm,
      ),
      child: Text(
        label.toUpperCase(),
        style: BrandType.eyebrow.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A quiet text action apart from the answers — *Remove this step*, *Use
/// Diamond's call*. Quiet because it is never the thing the dialog is for.
class QuietAction extends StatelessWidget {
  const QuietAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.accent = false,
    super.key,
  });

  final String label;
  final IconData? icon;

  /// Drawn in the accent: *Use Diamond's call*, which undoes the one thing
  /// on the dialog that carries it.
  final bool accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent
        ? (Theme.of(
                context,
              ).textButtonTheme.style?.foregroundColor?.resolve(const {}) ??
              scheme.primary)
        : scheme.onSurfaceVariant;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 48),
        textStyle: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      icon: icon == null ? null : Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// The dialog's footer: an optional [QuietAction] at the start, and *Done*
/// at the end.
class DialogDone extends StatelessWidget {
  const DialogDone({
    this.leading,
    this.doneKey,
    this.onDone,
    this.label = 'Done',
    super.key,
  });

  final Widget? leading;
  final Key? doneKey;

  /// *Done*, or what the scorer is acknowledging (*OK*, *Close*).
  final String label;

  /// Defaults to closing the dialog.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: BrandMetrics.spaceLg),
      child: Row(
        children: [
          ?leading,
          const Spacer(),
          OutlinedButton(
            key: doneKey,
            onPressed: onDone ?? () => Navigator.pop(context),
            // Ink, not the accent the theme gives an outlined label: Done
            // is never the datum (§23.7, board 16E).
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(96, 48),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              side: BorderSide(
                color: Theme.of(context).colorScheme.onSurface,
                width: 1.5,
              ),
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
