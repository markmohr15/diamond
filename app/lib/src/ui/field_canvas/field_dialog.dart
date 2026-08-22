import 'package:diamond/src/field/field_profile.dart';
import 'package:flutter/material.dart';

/// Every question the field surface asks (§15.1 v0.43): a centered dialog,
/// only as big as its content — and sized for a coach standing in a dugout
/// with the sun on the screen, not for a mouse. The chip and button themes
/// are scaled here rather than at each call site so one decision governs
/// every popup: trajectory, what-happened, SAFE/OUT, the ⚖ menus.
Future<T?> showFieldDialog<T>(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext) children,
  CrossAxisAlignment alignment = CrossAxisAlignment.center,
}) {
  final theme = Theme.of(context);
  const chipPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 16);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 36, vertical: 22);

  return showDialog<T>(
    context: context,
    builder: (context) => Theme(
      data: theme.copyWith(
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: theme.textTheme.titleMedium,
          padding: chipPadding,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            textStyle: theme.textTheme.titleMedium,
            padding: buttonPadding,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            textStyle: theme.textTheme.titleMedium,
            padding: buttonPadding,
          ),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: theme.textTheme.titleMedium,
          minVerticalPadding: 12,
        ),
      ),
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: alignment,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 20),
                // Built against the dialog's own context: anything that
                // pops with a result must pop *this* route.
                ...children(context),
              ],
            ),
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
    children: (dialogContext) => [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final entry in positionAbbreviations.entries)
            if (entry.key <= 9)
              ActionChip(
                key: positionPickKey(entry.key),
                label: Text(entry.value),
                onPressed: () => Navigator.pop(dialogContext, entry.key),
              ),
        ],
      ),
    ],
  );
}
