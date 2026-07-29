import 'package:diamond/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DiamondApp boots to the ZoneCanvas demo page', (
    WidgetTester tester,
  ) async {
    // The scope `main()` installs: DiamondApp reads its theme from the live
    // color context (§23.3), which lives above the MaterialApp.
    await tester.pumpWidget(const ProviderScope(child: DiamondApp()));

    expect(find.text('ZoneCanvas demo — DIA-005'), findsOneWidget);
  });
}
