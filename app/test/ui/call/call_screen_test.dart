import 'package:diamond/src/call/canonical_cells.dart';
import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/call/wristband_card.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  CallDraft draft() => container.read(callDraftProvider);

  Future<void> pumpScreen(
    WidgetTester tester, {
    BatterSide batterSide = BatterSide.R,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(
            deriveScheme(
              accentSeed: StubTeamColors.ownTeam.primary!,
              brightness: Brightness.light,
            ),
          ),
          home: Scaffold(body: CallScreen(batterSide: batterSide)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps the canvas at [coord], read in the **absolute** frame — which is what
  /// a finger on glass produces.
  Future<void> tapAt(WidgetTester tester, ZoneCoord coord) async {
    final area = find.byKey(zoneCanvasDrawingAreaKey);
    final size = tester.getSize(area);
    final topLeft = tester.getTopLeft(area);
    await tester.tapAt(topLeft + localFromZoneCoord(coord, size));
    await tester.pumpAndSettle();
  }

  Future<void> selectType(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  group('state 1 — no pitch chosen', () {
    testWidgets('the whole arsenal is on screen', (tester) async {
      await pumpScreen(tester);
      for (final type in StubTeamCallConfig.arsenal) {
        expect(find.text(type.name), findsOneWidget);
      }
    });

    testWidgets('the grid is visible but inert: a zone tap does nothing until '
        'a pitch is chosen (§10.1, type precedes zone)', (tester) async {
      await pumpScreen(tester);
      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));

      expect(draft().pending, isNull);
      expect(draft().hasType, isFalse);
    });
  });

  group('state 2 — pitch chosen', () {
    testWidgets('each pitch offers its own five locations, and no two pitches '
        'offer the same one', (tester) async {
      final config = container.read(teamCallConfigProvider);
      final seen = <String>{};
      for (final type in config.arsenal) {
        final ids = config.callableZones(type.id).map((z) => z.id).toSet();
        expect(ids, hasLength(5), reason: type.id);
        expect(
          seen.intersection(ids),
          isEmpty,
          reason: '${type.id} reuses a location another pitch already has',
        );
        seen.addAll(ids);
      }
      expect(seen, hasLength(20));
      expect(config.layout.zones, hasLength(25));
    });

    testWidgets('the pitches not chosen go away', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, 'Drop');

      expect(find.text('Drop'), findsOneWidget);
      expect(find.text('Fastball'), findsNothing);
      expect(find.text('Rise'), findsNothing);
    });

    testWidgets('the chips sit outside the drawing area, so they can never be '
        'in the way of a zone (§11.4)', (tester) async {
      await pumpScreen(tester);
      final canvas = tester.getRect(find.byKey(zoneCanvasDrawingAreaKey));
      final chips = tester.getRect(find.byKey(callScreenTypeRowKey));

      expect(canvas.overlaps(chips), isFalse);
      expect(chips.bottom, lessThanOrEqualTo(canvas.top));
    });
  });

  group('state 3 — zone chosen', () {
    testWidgets('two taps produce a pending call with a valid code', (
      tester,
    ) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));

      final pending = draft().pending!;
      expect(pending.pitchTypeId, 'ff');
      expect(pending.zoneId, 'c2r2'); // dead center
      expect(
        container.read(wristbandCardProvider).codesFor(pending.call),
        contains(pending.code),
      );
    });

    testWidgets('the zone carries the centroid of the cell that was tapped', (
      tester,
    ) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: -0.8, y: 0.2));

      final config = container.read(teamCallConfigProvider);
      final zone = config.layout.byId(draft().pending!.zoneId)!;

      // Low and inside for a righty: relative column 1, row 1.
      expect(zone.cells.single, const CanonicalCell(1, 1));
      expect(zone.centroid.x, closeTo(-2 / 3, 1e-12));
      expect(zone.centroid.y, closeTo(1 / 6, 1e-12));
    });

    testWidgets('the code renders huge (§10.3), above the pitch', (
      tester,
    ) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));

      final code = tester.widget<Text>(find.byKey(callScreenCodeKey));
      expect(code.style!.fontSize, greaterThanOrEqualTo(120));
      expect(
        tester.getRect(find.byKey(callScreenCodeKey)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(callScreenTypeRowKey)).top),
      );
      expect(code.data, draft().pending!.code);
    });

    testWidgets('the canvas does not move when the code appears — the plate '
        'is a registration landmark and must not jump', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      final before = tester.getRect(find.byKey(zoneCanvasDrawingAreaKey));

      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));
      expect(draft().pending, isNotNull);

      expect(tester.getRect(find.byKey(zoneCanvasDrawingAreaKey)), before);
    });

    testWidgets('the strip has a fixed height, so nothing about the text it '
        'holds can move the canvas', (tester) async {
      await pumpScreen(tester);
      final before = tester.getSize(find.byKey(callScreenTypeRowKey)).height;

      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));

      expect(tester.getSize(find.byKey(callScreenTypeRowKey)).height, before);
    });

    testWidgets('nor when the arsenal collapses to one chip', (tester) async {
      await pumpScreen(tester);
      final before = tester.getRect(find.byKey(zoneCanvasDrawingAreaKey));

      await selectType(tester, 'Fastball');

      expect(tester.getRect(find.byKey(zoneCanvasDrawingAreaKey)), before);
    });

    testWidgets('the code sits outside the drawing area too', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));

      final canvas = tester.getRect(find.byKey(zoneCanvasDrawingAreaKey));
      expect(
        canvas.overlaps(tester.getRect(find.byKey(callScreenCodeKey))),
        isFalse,
      );
    });

    testWidgets('a horizontal drag re-rolls: different code, same call', (
      tester,
    ) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));

      final before = draft().pending!;
      await tester.drag(
        find.byKey(zoneCanvasDrawingAreaKey),
        const Offset(140, 0),
      );
      await tester.pumpAndSettle();
      final after = draft().pending!;

      expect(after.code, isNot(before.code));
      expect(after.zoneId, before.zoneId);
      expect(after.pitchTypeId, before.pitchTypeId);
    });

    testWidgets('tapping a new zone replaces the pending call — nothing to '
        'undo, because nothing was committed (§10.3)', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));
      final first = draft().pending!;

      await tapAt(tester, ZoneCoord(x: -0.8, y: 0.2));
      final second = draft().pending!;

      expect(second.zoneId, isNot(first.zoneId));
    });
  });

  group('cancel', () {
    testWidgets('brings the whole arsenal back and drops the call', (
      tester,
    ) async {
      await pumpScreen(tester);
      await selectType(tester, 'Drop');
      // Mid-inside — one of the drop ball's five on this card.
      await tapAt(tester, ZoneCoord(x: -0.8, y: 0.5));
      expect(draft().pending, isNotNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(draft().hasType, isFalse);
      expect(draft().pending, isNull);
      for (final type in StubTeamCallConfig.arsenal) {
        expect(find.text(type.name), findsOneWidget);
      }
    });

    testWidgets('lives outside the drawing area, so it can never compete with '
        'a location tap', (tester) async {
      await pumpScreen(tester);
      final canvas = tester.getRect(find.byKey(zoneCanvasDrawingAreaKey));
      final cancel = tester.getRect(find.text('Cancel'));

      expect(canvas.overlaps(cancel), isFalse);
    });
  });

  group('handedness', () {
    testWidgets('"inside" is the batter\'s side: the same tap resolves to '
        'different zones for a righty and a lefty', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: -0.8, y: 0.2));
      final righty = draft().pending!.zoneId;

      container.read(callDraftProvider.notifier).clear();
      await pumpScreen(tester, batterSide: BatterSide.L);
      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: -0.8, y: 0.2));
      final lefty = draft().pending!.zoneId;

      // Screen-left is inside to a righty and away to a lefty (§3.1: positive
      // x is the first-base side).
      expect(righty, 'c1r1');
      expect(lefty, 'c3r1');
    });
  });

  group('narrowed pitch types', () {
    setUp(() {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          teamCallConfigProvider.overrideWithValue(
            StubTeamCallConfig.narrowedConfig(),
          ),
        ],
      );
    });

    testWidgets('the grid geometry does not move between pitch types — only '
        'which zones are callable (§10.3)', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      final before = tester.getRect(find.byKey(zoneCanvasDrawingAreaKey));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await selectType(tester, 'Change');

      expect(tester.getRect(find.byKey(zoneCanvasDrawingAreaKey)), before);
    });

    testWidgets('a tap on a zone this type cannot be called to is ignored, '
        'rather than snapping to the nearest one that can', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, 'Change');

      // Above the zone — a chase the change-up was narrowed out of.
      await tapAt(tester, ZoneCoord(x: 0, y: 1.2));
      expect(draft().pending, isNull);

      // The same type still calls in the zone.
      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));
      expect(draft().pending!.zoneId, 'c2r2');
    });
  });

  group('without wristbands (§10.2)', () {
    setUp(() {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          teamCallConfigProvider.overrideWithValue(
            StubTeamCallConfig.noWristbandConfig(),
          ),
        ],
      );
    });

    testWidgets('no code is shown — there is no card to read one from', (
      tester,
    ) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');
      await tapAt(tester, ZoneCoord(x: 0, y: 0.5));

      expect(find.byKey(callScreenCodeKey), findsNothing);
      // The intent is still captured; only the code is absent.
      expect(draft().pending!.zoneId, 'c2r2');
    });

    testWidgets('every zone the layout allows is callable', (tester) async {
      await pumpScreen(tester);
      await selectType(tester, 'Fastball');

      await tapAt(tester, ZoneCoord(x: 0, y: 1.2));
      expect(draft().pending!.zoneId, 'chase-high');
    });
  });

  testWidgets('nothing is offered that the active card cannot express', (
    tester,
  ) async {
    await pumpScreen(tester);
    final card = container.read(wristbandCardProvider);
    final config = container.read(teamCallConfigProvider);

    for (final type in config.arsenal) {
      for (final zone in config.callableZones(type.id)) {
        expect(
          card.canExpress(Call(pitchTypeId: type.id, zoneId: zone.id)),
          isTrue,
          reason: '${type.id}@${zone.id} is offerable but has no code',
        );
      }
    }
  });
}
