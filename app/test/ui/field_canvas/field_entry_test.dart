import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_journal_store.dart';
import 'package:diamond/src/ui/field_canvas/field_entry_surface.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:diamond/src/ui/loop/pitch_loop_page.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// DIA-008a acceptance: the field surface end-to-end — landing (both grips),
/// live distance, trajectory, runner drags, atomic ✓ (§15.5), the journal
/// restore, and the committed play as one undo unit.
void main() {
  // One database across containers, so the restore tests can relaunch "the
  // app" (a fresh container) against surviving storage.
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// A second launch of the app over the same database.
  ProviderContainer relaunch() {
    final next = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(next.dispose);
    return next;
  }

  Future<void> pumpLoop(WidgetTester tester, {ProviderContainer? into}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: into ?? container,
        child: MaterialApp(
          theme: buildTheme(
            deriveScheme(
              accentSeed: StubTeamColors.ownTeam.primary!,
              brightness: Brightness.light,
            ),
          ),
          home: const PitchLoopPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<GameEvent>> stream({ProviderContainer? from}) {
    final c = from ?? container;
    final session = c.read(gameSessionProvider);
    return c.read(eventStoreProvider).readStream(session.gameId);
  }

  /// Fastest path to the field surface: skip call, skip location, "In play".
  Future<void> reachFieldSurface(WidgetTester tester) async {
    await tester.tap(find.text('Skip call'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In play'));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldCanvasKey), findsOneWidget);
  }

  /// The rendered canvas's geometry, for aiming taps at world coordinates.
  FieldGeometry canvasGeometry(WidgetTester tester) => FieldGeometry(
    profile: FieldProfile.fastpitch12U,
    size: tester.getSize(find.byKey(fieldCanvasKey)),
  );

  Offset canvasTopLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(fieldCanvasKey));

  Future<void> tapLanding(WidgetTester tester, FieldCoord world) async {
    final geometry = canvasGeometry(tester);
    await tester.tapAt(canvasTopLeft(tester) + geometry.toPx(world));
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('reaching the field surface (§11.1: in_play → FIELD)', () {
    testWidgets('the in-play outcome opens the canvas; ✓ is disabled until '
        'landing and trajectory exist', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);

      expect(find.byType(ZoneCanvas), findsNothing);
      expect(find.text('Tap the landing spot'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(fieldCommitKey)).onPressed,
        isNull,
      );
    });
  });

  group('landing entry (§15.1, §16.3)', () {
    testWidgets('a tap records landing alone and shows its distance', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapLanding(tester, FieldCoord(x: -45, y: 120));

      // √(45² + 120²) ≈ 128 ft, computed from the profile-scaled canvas.
      expect(find.text('128 ft'), findsOneWidget);
      // Landing without trajectory: still not committable.
      expect(
        tester.widget<FilledButton>(find.byKey(fieldCommitKey)).onPressed,
        isNull,
      );
    });

    testWidgets('tap-and-drag records landing at touch-down and the roll at '
        'release (§15.1 both grips)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);

      final geometry = canvasGeometry(tester);
      final topLeft = canvasTopLeft(tester);
      await drag(
        tester,
        topLeft + geometry.toPx(FieldCoord(x: -60, y: 140)),
        topLeft + geometry.toPx(FieldCoord(x: -80, y: 185)),
      );

      final label = tester.widget<Text>(find.byKey(fieldDistanceKey)).data!;
      expect(label, contains('→'));
      expect(label, contains('152 ft')); // √(60²+140²)

      await tester.tap(find.byKey(trajectoryKey(Trajectory.LINE)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldCommitKey));
      await tester.pumpAndSettle();

      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.landing.x, closeTo(-60, 2));
      expect(ball.landing.y, closeTo(140, 2));
      expect(ball.retrieved!.x, closeTo(-80, 2));
      expect(ball.retrieved!.y, closeTo(185, 2));
      expect(ball.trajectory, Trajectory.LINE);
    });

    testWidgets('a landing on the fence spline suggests off-the-wall '
        '(§15.1)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);

      expect(find.byKey(offWallChipKey), findsNothing);
      await tapLanding(tester, FieldCoord(x: 0, y: 208));
      expect(find.byKey(offWallChipKey), findsOneWidget);

      await tester.tap(find.byKey(offWallChipKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(trajectoryKey(Trajectory.FLY)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldCommitKey));
      await tester.pumpAndSettle();

      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.offWall, isTrue);
    });
  });

  group('the clean single, end to end (DIA-008a accept)', () {
    testWidgets('landing → trajectory → batter-runner to first → ✓ commits '
        'atomically and the loop returns to the call screen', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);

      await tapLanding(tester, FieldCoord(x: 110, y: 180));
      await tester.tap(find.byKey(trajectoryKey(Trajectory.LINE)));
      await tester.pumpAndSettle();

      // Drag the batter token from the plate to first.
      final geometry = canvasGeometry(tester);
      final topLeft = canvasTopLeft(tester);
      await drag(
        tester,
        topLeft + geometry.tokenCenter(0),
        topLeft + geometry.baseCenter(1),
      );

      await tester.tap(find.byKey(fieldCommitKey));
      await tester.pumpAndSettle();

      // Back on the loop; play in the stream in order; batter on first.
      expect(find.byKey(fieldCanvasKey), findsNothing);
      expect(find.text('Skip call'), findsOneWidget);

      final events = await stream();
      final types = events.map((e) => e.type).toList();
      expect(types.sublist(types.length - 3), [
        'PitchThrown',
        'BallInPlay',
        'RunnerAdvance',
      ]);
      final advance = RunnerAdvance.fromJson(events.last.payload);
      expect(advance.runnerId, 'opp-1');
      expect(advance.from, 0);
      expect(advance.to, 1);
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);

      final state = container.read(gameControllerProvider).value!;
      expect(state.bases.first, 'opp-1');

      // The journal is spent (§15.5): a relaunch shows the loop, not the
      // canvas.
      final session = container.read(gameSessionProvider);
      expect(
        await container.read(playJournalStoreProvider).load(session.gameId),
        isNull,
      );

      // The unlocated in-play pitch's standing offer survives the play
      // (§11.1 v0.39).
      expect(find.byKey(recordLastPitchKey), findsOneWidget);
    });

    testWidgets('dragging the batter onto an occupied first walks the chain '
        'up — the forced cascade, adjustable by re-drag', (tester) async {
      await pumpLoop(tester);

      // Walk opp-1 aboard: four skipped-entry balls (§11.3 auto-applies the
      // forced advance).
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Skip call'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Skip location'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ball'));
        await tester.pumpAndSettle();
      }

      // opp-2 puts it in play and beats it out; opp-1 is pushed to second
      // by the drag itself — no second gesture.
      await reachFieldSurface(tester);
      await tapLanding(tester, FieldCoord(x: 60, y: 110));
      await tester.tap(find.byKey(trajectoryKey(Trajectory.GROUND)));
      await tester.pumpAndSettle();

      final geometry = canvasGeometry(tester);
      final topLeft = canvasTopLeft(tester);
      await drag(
        tester,
        topLeft + geometry.tokenCenter(0),
        topLeft + geometry.baseCenter(1),
      );
      await tester.tap(find.byKey(fieldCommitKey));
      await tester.pumpAndSettle();

      final state = container.read(gameControllerProvider).value!;
      expect(state.bases.first, 'opp-2');
      expect(state.bases.second, 'opp-1');

      final events = await stream();
      final advances = events
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .toList();
      // The walk's forced advance, then the play's two: batter to first,
      // the push to second — both batted_ball.
      expect(advances, hasLength(3));
      expect(advances.sublist(1).map((a) => (a.runnerId, a.from, a.to)), [
        ('opp-2', 0, 1),
        ('opp-1', 1, 2),
      ]);
      expect(advances.sublist(1).map((a) => a.reason).toSet(), {
        RunnerAdvanceReason.BATTED_BALL,
      });
    });

    testWidgets('one undo voids the committed play as a unit, leaving the '
        'pitch (§11.3 action scope)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapLanding(tester, FieldCoord(x: 110, y: 180));
      await tester.tap(find.byKey(trajectoryKey(Trajectory.LINE)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldCommitKey));
      await tester.pumpAndSettle();

      await container.read(gameControllerProvider.notifier).undoLast();
      final types = (await stream()).map((e) => e.type).toList();
      expect(types, isNot(contains('BallInPlay')));
      expect(types, contains('PitchThrown'));
    });
  });

  group('discard and restore (§15.5)', () {
    testWidgets('discard abandons the play but keeps the pitch', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapLanding(tester, FieldCoord(x: 0, y: 100));
      await tester.tap(find.byKey(fieldDiscardKey));
      await tester.pumpAndSettle();

      expect(find.byKey(fieldCanvasKey), findsNothing);
      final types = (await stream()).map((e) => e.type).toList();
      expect(types, contains('PitchThrown'));
      expect(types, isNot(contains('BallInPlay')));
    });

    testWidgets('kill mid-play, relaunch: the canvas restores with landing '
        'and trajectory intact (DIA-008 accept)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapLanding(tester, FieldCoord(x: -45, y: 120));
      await tester.tap(find.byKey(trajectoryKey(Trajectory.GROUND)));
      await tester.pumpAndSettle();

      // "Kill the app": tear the widget tree down and relaunch on a fresh
      // container — only the database survives, exactly like a real death.
      // (The first container is merely abandoned; tearDown disposes it.)
      await tester.pumpWidget(const SizedBox());

      final second = relaunch();
      await pumpLoop(tester, into: second);

      expect(find.byKey(fieldCanvasKey), findsOneWidget);
      expect(find.text('128 ft'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(trajectoryKey(Trajectory.GROUND)))
            .selected,
        isTrue,
      );

      // And the restored draft still commits.
      await tester.tap(find.byKey(fieldCommitKey));
      await tester.pumpAndSettle();
      final types = (await stream(from: second)).map((e) => e.type).toList();
      expect(types.last, 'BallInPlay');
    });
  });
}
