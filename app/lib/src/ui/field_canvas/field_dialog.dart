import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/ui/dialog/dialog_parts.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:material_ui/material_ui.dart';

/// Every question the field surface asks (§15.1 v0.43): a centered dialog,
/// only as big as its content.
///
/// It used to scale its own chip, button and list-tile themes here, because
/// there was nothing shared to reach for — which meant every popup on the
/// field surface inherited its sizing from this one function by accident of
/// history, and nothing outside the field got it at all. DIA-016d moved those
/// decisions onto the theme (`buildTheme`), so what is left here is the only
/// part that was ever specific to this dialog: **its layout**.
///
/// §23.7 (v0.77) makes this the frame for **every** dialog in the app, not
/// just the field's: the title names what was tapped, [question] asks in
/// words, and the answers are `dialog_parts.dart`'s.
Future<T?> showFieldDialog<T>(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext) children,
  String? question,
  CrossAxisAlignment alignment = CrossAxisAlignment.stretch,
}) {
  final theme = Theme.of(context);

  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        // A measure, not a breakpoint: past this the eye loses the start of
        // the next line, and these are read at a glance.
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(BrandMetrics.space3xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: alignment,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (question != null)
                Padding(
                  padding: const EdgeInsets.only(top: BrandMetrics.spaceXs),
                  child: Text(
                    question,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: BrandMetrics.spaceLg),
              // Built against the dialog's own context: anything that
              // pops with a result must pop *this* route.
              ...children(context),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Keys the widget tests resolve against.
@visibleForTesting
Key positionPickKey(int position) => Key('positionPick-$position');

/// Which fielder a rule call is against (§4.5). Obstruction is charged to
/// her (§13.2 v0.43), so the call cannot be recorded without a name — and
/// interference wants the same answer for the development record.
Future<int?> showPositionPicker(BuildContext context, String title) {
  return showFieldDialog<int>(
    context,
    title: title,
    question: 'The fielder the call is against.',
    children: (dialogContext) => [
      AnswerGrid(
        columns: 3,
        children: [
          for (final entry in positionAbbreviations.entries)
            if (entry.key <= 9)
              AnswerButton(
                key: positionPickKey(entry.key),
                label: entry.value,
                onPressed: () => Navigator.pop(dialogContext, entry.key),
              ),
        ],
      ),
      const DialogDone(),
    ],
  );
}
