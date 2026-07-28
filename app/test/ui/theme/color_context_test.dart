import 'package:diamond/src/ui/theme/brand_baseline.dart';
import 'package:diamond/src/ui/theme/color_context.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:diamond/src/ui/theme/theme_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scheme_tokens.dart';

/// Reads the resolved theme from *below* the `MaterialApp`, which is the only
/// place that proves the swap reached widgets rather than only the provider.
///
/// Every swap here settles before it is read: `MaterialApp` wraps its theme in
/// an `AnimatedTheme`, so a single pump lands mid-crossfade on a lerped scheme
/// that belongs to neither team.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late ProviderContainer container;

  Future<ThemeData> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ref.watch(lightThemeProvider),
            darkTheme: ref.watch(darkThemeProvider),
            home: const _Probe(),
          ),
        ),
      ),
    );
    return Theme.of(tester.element(find.byType(_Probe)));
  }

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  testWidgets('the default context is own-team (§23.3)', (tester) async {
    final theme = await pumpApp(tester);

    expect(container.read(colorContextProvider), ColorContext.ownTeam);
    expect(theme.colorScheme.primary, StubTeamColors.ownTeam.primary);
  });

  testWidgets('entering an opponent swaps the accent app-wide and leaves the '
      'brand chrome untouched', (tester) async {
    final own = await pumpApp(tester);
    final ownTokens = schemeTokens(own.colorScheme);

    container.read(colorContextProvider.notifier).enterOpponent('hawks');
    await tester.pumpAndSettle();
    final opponent = Theme.of(tester.element(find.byType(_Probe)));

    expect(
      opponent.colorScheme.primary,
      StubTeamColors.opponentById('hawks')!.primary,
    );

    final differing = {
      for (final name in ownTokens.keys)
        if (ownTokens[name] != schemeTokens(opponent.colorScheme)[name]) name,
    };
    expect(differing, isNotEmpty);
    expect(differing.difference(accentTokenNames), isEmpty);

    // Tier 1 is untouched: the accent moves, the app does not become the other
    // team's app (§23.3).
    expect(opponent.appBarTheme.backgroundColor, BrandBaseline.light.chrome);
    expect(
      opponent.appBarTheme.backgroundColor,
      own.appBarTheme.backgroundColor,
    );
    expect(opponent.scaffoldBackgroundColor, own.scaffoldBackgroundColor);
  });

  testWidgets('leaving restores the own-team accent exactly', (tester) async {
    final own = await pumpApp(tester);
    final before = schemeTokens(own.colorScheme);

    container.read(colorContextProvider.notifier).enterOpponent('hawks');
    await tester.pumpAndSettle();
    container.read(colorContextProvider.notifier).exit();
    await tester.pumpAndSettle();

    final after = Theme.of(tester.element(find.byType(_Probe)));
    expect(schemeTokens(after.colorScheme), before);
  });

  testWidgets('an opponent with no colour set falls back to the baseline '
      'accent rather than inventing one (§23.3)', (tester) async {
    await pumpApp(tester);

    container.read(colorContextProvider.notifier).enterOpponent('storm');
    await tester.pumpAndSettle();

    expect(StubTeamColors.opponentById('storm')!.primary, isNull);
    expect(
      Theme.of(tester.element(find.byType(_Probe))).colorScheme.primary,
      StubTeamColors.ownTeam.primary,
    );
  });

  testWidgets('an unknown opponent id falls back too', (tester) async {
    await pumpApp(tester);

    container.read(colorContextProvider.notifier).enterOpponent('no-such-team');
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(_Probe))).colorScheme.primary,
      StubTeamColors.ownTeam.primary,
    );
  });

  testWidgets('dark mode swaps with it — night games are real (§23.1.4)', (
    tester,
  ) async {
    container.read(colorContextProvider.notifier).enterOpponent('hawks');
    await pumpApp(tester);

    final dark = container.read(darkThemeProvider);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(
      dark.colorScheme.primary,
      StubTeamColors.opponentById('hawks')!.primary,
    );
    expect(dark.colorScheme.surface, BrandBaseline.dark.surface);
  });
}
