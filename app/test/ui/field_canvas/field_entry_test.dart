import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_journal_store.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/field_canvas/field_entry_surface.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/play_chain_strip.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:diamond/src/ui/loop/count_hud.dart';
import 'package:diamond/src/ui/loop/outcome_step.dart';
import 'package:diamond/src/ui/loop/pitch_loop_page.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// DIA-008a/b acceptance under §15.1 v0.43's grammar: the trajectory modal
/// first; the ball's path drawn (two taps, streak) or implied by the live
/// fielder drag with its what-happened popup; the batter runs on contact;
/// SAFE/OUT resolution at the approached base; the chain strip's chips; the
/// §15.4.2 prompt; atomic ✓ (§15.5); the journal restore; and the committed
/// play as one undo unit.
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
  /// Arrives with the trajectory modal open (§15.1 v0.43).
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

  Offset worldPx(WidgetTester tester, FieldCoord world) =>
      canvasTopLeft(tester) + canvasGeometry(tester).toPx(world);

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> tapWorld(WidgetTester tester, FieldCoord world) async {
    await tester.tapAt(worldPx(tester, world));
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

  FieldCoord standardSpot(int position) =>
      standardFielderSpots(FieldProfile.fastpitch12U)[position]!;

  /// Drags [position] from her standard spot to where she made the play.
  Future<void> dragFielder(
    WidgetTester tester,
    int position,
    FieldCoord to,
  ) async {
    await drag(
      tester,
      worldPx(tester, standardSpot(position)),
      worldPx(tester, to),
    );
  }

  /// A throw: from the holder's current spot to the receiver's spot.
  Future<void> dragBall(
    WidgetTester tester,
    FieldCoord from,
    FieldCoord to,
  ) async {
    await drag(tester, worldPx(tester, from), worldPx(tester, to));
  }

  /// Drags the token at [fromBase] and releases it on [target] at [toBase]:
  /// the SAFE pill, the OUT pill, or the base itself (also safe).
  /// [originFrom] names the base the play found her on when she is still
  /// in motion (the walk-up), since the token renders partway up the line.
  Future<void> dragToken(
    WidgetTester tester,
    int fromBase,
    int toBase, {
    String target = 'safe',
    int? originFrom,
  }) async {
    final geometry = canvasGeometry(tester);
    final release = switch (target) {
      'out' => geometry.outAffordanceCenter(toBase),
      'safe' => geometry.safeAffordanceCenter(toBase),
      _ => toBase == 4 ? geometry.plate : geometry.baseCenter(toBase),
    };
    await drag(
      tester,
      canvasTopLeft(tester) +
          geometry.runnerTokenCenter(
            base: fromBase,
            origin: originFrom,
            inMotion: originFrom != null,
          ),
      canvasTopLeft(tester) + release,
    );
  }

  /// Taps the pending force play's SAFE or OUT pill at [base].
  Future<void> tapPill(
    WidgetTester tester,
    int base, {
    bool out = false,
  }) async {
    final geometry = canvasGeometry(tester);
    final center = out
        ? geometry.outAffordanceCenter(base)
        : geometry.safeAffordanceCenter(base);
    await tester.tapAt(canvasTopLeft(tester) + center);
    await tester.pumpAndSettle();
  }

  /// Runs a fixture's gesture script asserting the DIA-008 tap budget: the
  /// list length IS the field-gesture count the ticket documents.
  Future<void> runGestures(
    int budget,
    List<Future<void> Function()> gestures,
  ) async {
    expect(gestures, hasLength(budget), reason: 'ticket tap budget');
    for (final gesture in gestures) {
      await gesture();
    }
  }

  group('reaching the field surface (§11.1: in_play → FIELD)', () {
    testWidgets('the trajectory modal opens with the surface; canvas '
        'touches bring it back until answered (§15.1 v0.43)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      expect(find.text('How did it come off the bat?'), findsOneWidget);

      // Wave it away; the canvas just re-asks.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('How did it come off the bat?'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(fieldCommitKey)).onPressed,
        isNull,
      );

      await tapWorld(tester, FieldCoord(x: -45, y: 120));
      expect(find.text('How did it come off the bat?'), findsOneWidget);

      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      expect(find.text('How did it come off the bat?'), findsNothing);
      await tapWorld(tester, FieldCoord(x: -45, y: 120));
      expect(find.text('128 ft'), findsOneWidget);
    });
  });

  group('the drawn path (§15.1 v0.43: two taps, the streak)', () {
    testWidgets('first tap = first bounce, second = where it ended up; '
        'later taps adjust the end', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));

      await tapWorld(tester, FieldCoord(x: -60, y: 140));
      expect(find.text('152 ft'), findsOneWidget); // √(60²+140²)

      await tapWorld(tester, FieldCoord(x: -70, y: 160));
      final label = tester.widget<Text>(find.byKey(fieldDistanceKey)).data!;
      expect(label, '152 ft → 175 ft');

      await tapWorld(tester, FieldCoord(x: -75, y: 165));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.landing.x, closeTo(-60, 2));
      expect(ball.landing.y, closeTo(140, 2));
      expect(ball.endedAt!.x, closeTo(-75, 2));
      expect(ball.endedAt!.y, closeTo(165, 2));
      expect(ball.trajectory, Trajectory.GROUND);
    });

    testWidgets('a landing on the fence spline suggests off-the-wall '
        '(§15.1)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));

      expect(find.byKey(offWallChipKey), findsNothing);
      await tapWorld(tester, FieldCoord(x: 0, y: 208));
      expect(find.byKey(offWallChipKey), findsOneWidget);

      await tapKey(tester, offWallChipKey);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.offWall, isTrue);
    });
  });

  group(
    'the fielder drag (§15.1 v0.43: play implied, popup disambiguates)',
    () {
      testWidgets('drag 8 to the ball, Caught: the walk-up voids and the fly '
          'out records itself — four gestures, done', (tester) async {
        await pumpLoop(tester);
        await reachFieldSurface(tester);

        await runGestures(4, [
          () => tapKey(tester, trajectoryKey(Trajectory.FLY)),
          () => dragFielder(tester, 8, FieldCoord(x: 30, y: 160)),
          () => tapKey(tester, fielderPlayKey('caught')),
          () => tapKey(tester, fieldCommitKey),
        ]);

        final events = await stream();
        expect(events.map((e) => e.type), isNot(contains('RunnerAdvance')));
        final ball = BallInPlay.fromJson(
          events.lastWhere((e) => e.type == 'BallInPlay').payload,
        );
        expect(ball.landing.x, closeTo(30, 2));
        expect(ball.landingIsCaught, isTrue);

        final touchEvent = events.lastWhere((e) => e.type == 'FielderTouch');
        final touch = FielderTouch.fromJson(touchEvent.payload);
        expect(touch.touchType, TouchType.CAUGHT);
        expect(touch.position, 8);
        expect(touch.location!.x, closeTo(30, 2));

        final out = events.lastWhere((e) => e.type == 'RunnerOut');
        expect(out.payload['how'], 'fly_out');
        expect(out.payload['putoutTouchId'], touchEvent.id);
        expect(container.read(gameControllerProvider).value!.outs, 1);
      });

      testWidgets('ground ball popup offers ground choices; "Missed it" '
          'records no touch and the batter reaches (§13)', (tester) async {
        await pumpLoop(tester);
        await reachFieldSurface(tester);
        await tapKey(tester, trajectoryKey(Trajectory.GROUND));

        await dragFielder(tester, 4, FieldCoord(x: 30, y: 95));
        expect(find.byKey(fielderPlayKey('caught')), findsNothing);
        expect(find.byKey(fielderPlayKey('fielded')), findsOneWidget);
        await tapKey(tester, fielderPlayKey('missed'));
        await tapKey(tester, fieldCommitKey);

        final events = await stream();
        expect(events.map((e) => e.type), isNot(contains('FielderTouch')));
        final ball = BallInPlay.fromJson(
          events.lastWhere((e) => e.type == 'BallInPlay').payload,
        );
        expect(ball.landing.x, closeTo(30, 2));
        final advance = RunnerAdvance.fromJson(events.last.payload);
        expect(advance.runnerId, 'opp-1');
        expect(advance.to, 1);
      });
    },
  );

  group('throws (§15.1 v0.43: tap while the ball is held)', () {
    testWidgets('with the ball secured, tapping another fielder throws to '
        'her — received_throw at her spot, ball route drawn', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('fielded'));

      await tapWorld(tester, standardSpot(3)); // the throw, one tap
      // No popup: a throw is not a new play on the ball. The force play's
      // SAFE/OUT pair is up instead — she beat it.
      expect(find.byKey(fielderPlayKey('fielded')), findsNothing);
      await tapPill(tester, 1);
      // v0.56: the pill asks the same question the drag does.
      await tapKey(tester, safeChipKey('hit'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches, hasLength(2));
      expect(touches.last.payload['touchType'], 'received_throw');
      expect(touches.last.payload['position'], 3);
      final location = touches.last.payload['location'] as Map<String, dynamic>;
      expect(location['x'] as double, closeTo(standardSpot(3).x, 2));
    });

    testWidgets('Deflected on a grounder: it hit her and caromed away — a '
        'touch, no error, and the ball is loose (§13.2)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));

      await dragFielder(tester, 5, FieldCoord(x: -55, y: 85));
      expect(find.text('Deflected'), findsOneWidget);
      await tapKey(tester, fielderPlayKey('deflected'));

      // Loose, so the next fielder is playing the ball, not receiving it.
      await tapWorld(tester, standardSpot(6));
      expect(find.byKey(fielderPlayKey('fielded')), findsOneWidget);
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches, hasLength(2));
      expect(touches.first.payload['touchType'], 'deflected');
      expect(touches.first.payload['position'], 5);
      // Her reach stands as a hit: a deflection is not a misplay, so it
      // never claims the batter's provisional reach (§13.2).
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
      expect(advance.to, 1);
    });

    testWidgets('Deflected is not offered in the air', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      expect(find.text('Deflected'), findsNothing);
      expect(find.text('Caught'), findsOneWidget);
    });

    testWidgets('the simple 6-3: field it, throw to first, OUT — five '
        'gestures, no runner dragging at all', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);

      await runGestures(5, [
        () => tapKey(tester, trajectoryKey(Trajectory.GROUND)),
        () => dragFielder(tester, 6, FieldCoord(x: -40, y: 90)),
        () => tapKey(tester, fielderPlayKey('fielded')),
        () => tapWorld(tester, standardSpot(3)), // the throw
        () => tapPill(tester, 1, out: true), // the force play, resolved
      ]);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final tail = events.sublist(events.length - 4);
      expect(tail.map((e) => e.type), [
        'BallInPlay',
        'FielderTouch',
        'FielderTouch',
        'RunnerOut',
      ]);
      expect(tail[1].payload['touchType'], 'fielded');
      expect(tail[2].payload['touchType'], 'received_throw');
      expect(tail[3].payload['how'], 'force');
      expect(tail[3].payload['putoutTouchId'], tail[2].id);
      expect(container.read(gameControllerProvider).value!.outs, 1);
      expect(container.read(gameControllerProvider).value!.bases.first, isNull);
    });

    testWidgets('a drop leaves the ball at her feet; one tap on her says it '
        'caromed, and then the next fielder is picking it up', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 10, y: 150));
      await tapKey(tester, fielderPlayKey('dropped'));

      // A drop leaves the ball at her feet, so Diamond shows CF holding it
      // and the next fielder tapped would be receiving a throw. It caromed
      // away instead — one tap on CF says so, and the ball is loose again
      // (§15.1 v0.56). That gesture is the whole escape hatch for a
      // possession Diamond inferred wrongly.
      await tapWorld(tester, FieldCoord(x: 10, y: 150)); // where she stands
      // LF coming over is now a pickup, not a reception — the popup asks,
      // and it no longer offers to catch a ball that is already down.
      await tapWorld(tester, standardSpot(7));
      expect(find.text('Caught'), findsNothing);
      expect(find.byKey(fielderPlayKey('fielded')), findsOneWidget);
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapKey(tester, fieldCommitKey);
      // The drop opened the play, so the ✓ asks what it cost before it
      // commits, and the answer names the charge (§13.2 v0.56).
      await tapKey(tester, safeChipKey('error-catching-8'));

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches, hasLength(2));
      expect(touches.last.payload['touchType'], 'fielded');
      expect(touches.last.payload['position'], 7);
    });
  });

  group('beyond the fence (§16.3)', () {
    testWidgets('a fair landing past the fence asks "Home run?" — Yes '
        'scores everyone aboard', (tester) async {
      await pumpLoop(tester);
      // A runner on first, so the home run is a two-run shot.
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r1',
              from: 0,
              to: 1,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);

      await runGestures(4, [
        () => tapKey(tester, trajectoryKey(Trajectory.FLY)),
        () => tapWorld(tester, FieldCoord(x: 0, y: 220)), // past the 210 CF
        () => tapKey(tester, beyondFenceKey('yes')),
        () => tapKey(tester, fieldCommitKey),
      ]);

      final events = await stream();
      final advances = events
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .toList();
      // The setup advance, then the two scoring legs — lead runner first.
      expect(advances.sublist(1).map((a) => (a.runnerId, a.from, a.to)), [
        ('r1', 1, 4),
        ('opp-1', 0, 4),
      ]);
      expect(
        advances
            .sublist(1)
            .every((a) => a.reason == RunnerAdvanceReason.BATTED_BALL),
        isTrue,
      );

      final state = container.read(gameControllerProvider).value!;
      expect(state.runsByTeam['opp'], 2);
      expect(state.bases.first, isNull);
      expect(state.bases.second, isNull);
      expect(state.bases.third, isNull);
      expect(state.outs, 0);
    });

    testWidgets('a landing inside the fence never asks', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await tapWorld(tester, FieldCoord(x: 0, y: 180));
      expect(find.text('Home run?'), findsNothing);
    });

    testWidgets('No proceeds as a normal play — the landing stands and the '
        'walk-up is untouched', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await tapWorld(tester, FieldCoord(x: 0, y: 220));
      await tapKey(tester, beyondFenceKey('no'));
      await tapKey(tester, fieldCommitKey);

      final committed = await stream();
      final ball = BallInPlay.fromJson(
        committed.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.landing.y, closeTo(220, 2));
      final walkUp = RunnerAdvance.fromJson(committed.last.payload);
      expect(walkUp.to, 1, reason: 'the ordinary walk-up, nothing awarded');
      expect(
        container.read(gameControllerProvider).value!.runsByTeam['opp'] ?? 0,
        0,
      );
    });

    testWidgets('landed in the park, ended up over the fence: asks '
        '"Ground rule double?" — Yes awards two bases apiece', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      await tapWorld(tester, FieldCoord(x: 0, y: 170)); // lands in the park
      expect(find.text('Home run?'), findsNothing);

      await tapWorld(tester, FieldCoord(x: 0, y: 220)); // bounces over
      expect(find.text('Ground rule double?'), findsOneWidget);
      await tapKey(tester, beyondFenceKey('yes'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advance = RunnerAdvance.fromJson(events.last.payload);
      expect(advance.runnerId, 'opp-1');
      expect(advance.to, 2);
      expect(advance.reason, RunnerAdvanceReason.GROUND_RULE);
      expect(
        container.read(gameControllerProvider).value!.bases.second,
        'opp-1',
      );
    });
  });

  group('the ball decides what can happen next (§15.1 v0.43)', () {
    testWidgets('once it has been touched it is a ball on the ground: no '
        'catching it, whatever it was off the bat', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      expect(find.text('Caught'), findsOneWidget);
      await tapKey(tester, fielderPlayKey('dropped'));

      await tapWorld(tester, FieldCoord(x: 20, y: 170)); // CF does not have it
      await tapWorld(tester, standardSpot(9));
      expect(find.text('Caught'), findsNothing);
      expect(find.text('Fielded'), findsOneWidget);
      // Mark, 2026-09-04: outfielders can't deflect, they can only miss.
      expect(find.text('Deflected'), findsNothing);
    });

    testWidgets('a liner caroms: deflected off the pitcher, still in the '
        'air, caught by the shortstop for the out', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.LINE));

      await dragFielder(tester, 1, FieldCoord(x: 2, y: 44));
      expect(find.text('Deflected'), findsOneWidget);
      await tapKey(tester, fielderPlayKey('deflected'));

      // Off the glove and still up: the shortstop can catch it.
      await tapWorld(tester, standardSpot(6));
      expect(find.text('Caught'), findsOneWidget);
      await tapKey(tester, fielderPlayKey('caught'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches.map((e) => e.payload['touchType']), [
        'deflected',
        'caught',
      ]);
      // The catch retires her wherever it happened — but the ball was not
      // caught where it came down, so the wire field stays honest.
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.landingIsCaught, isFalse);
      final out = events.lastWhere((e) => e.type == 'RunnerOut');
      expect(out.payload['how'], 'fly_out');
      expect(out.payload['putoutTouchId'], touches.last.id);
      expect(events.map((e) => e.type), isNot(contains('RunnerAdvance')));
    });

    testWidgets('a fly ball is never deflected — one fielder touching it '
        'and another catching it is two fielders on one ball', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.POPUP));
      await dragFielder(tester, 5, FieldCoord(x: -30, y: 50));
      expect(find.text('Caught'), findsOneWidget);
      expect(find.text('Deflected'), findsNothing);
    });

    testWidgets('dropping a runner on the base she already occupies is not '
        'a move — no from==to leg, and she settles', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));

      // She is walking up to first; drag her onto first.
      await dragToken(tester, 1, 1, originFrom: 0);
      expect(find.text('Safe at 1B — how?'), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advances = events
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .toList();
      expect(advances, hasLength(1), reason: 'the walk-up, and only that');
      expect(advances.single.from, 0);
      expect(advances.single.to, 1);
      expect(
        container.read(gameControllerProvider).value!.bases.first,
        'opp-1',
      );
    });
  });

  group('the batter runs on contact (§15.1 v0.43)', () {
    testWidgets('a clean single is trajectory + tap + ✓ — the walk-up '
        'commits by itself and the loop returns', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);

      await runGestures(3, [
        () => tapKey(tester, trajectoryKey(Trajectory.LINE)),
        () => tapWorld(tester, FieldCoord(x: 110, y: 150)), // inside the yard
        () => tapKey(tester, fieldCommitKey),
      ]);

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

      // The journal is spent (§15.5); the standing offer survives the play
      // (§11.1 v0.39).
      final session = container.read(gameSessionProvider);
      expect(
        await container.read(playJournalStoreProvider).load(session.gameId),
        isNull,
      );
      expect(find.byKey(recordLastPitchKey), findsOneWidget);
    });

    testWidgets('with first occupied the walk-up cascades — the whole chain '
        'moves with zero drags', (tester) async {
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

      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: 60, y: 110));
      await tapKey(tester, fieldCommitKey);

      final state = container.read(gameControllerProvider).value!;
      expect(state.bases.first, 'opp-2');
      expect(state.bases.second, 'opp-1');

      final events = await stream();
      final advances = events
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .toList();
      expect(advances, hasLength(3)); // the walk, then the play's two
      expect(advances.sublist(1).map((a) => (a.runnerId, a.from, a.to)), [
        ('opp-2', 0, 1),
        ('opp-1', 1, 2),
      ]);
    });

    testWidgets('one undo voids the committed play as a unit, leaving the '
        'pitch (§11.3 action scope)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      await tapWorld(tester, FieldCoord(x: 110, y: 150));
      await tapKey(tester, fieldCommitKey);

      await container.read(gameControllerProvider.notifier).undoLast();
      final types = (await stream()).map((e) => e.type).toList();
      expect(types, isNot(contains('BallInPlay')));
      expect(types, isNot(contains('RunnerAdvance')));
      expect(types, contains('PitchThrown'));
    });
  });

  group('fixtures through the UI (DIA-008 accept)', () {
    testWidgets('play 01 — dropped liner, out anyway: 6 field gestures', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      final spot = FieldCoord(x: -45, y: 120);

      // Six, not eight (v0.56): a drop leaves the ball at her feet, so the
      // scorer no longer tells Diamond she picked it up — throwing it is
      // the proof, and the recovery touch is minted there.
      await runGestures(6, [
        () => tapKey(tester, trajectoryKey(Trajectory.LINE)),
        () => dragFielder(tester, 6, spot), // she goes to the ball
        () => tapKey(tester, fielderPlayKey('dropped')),
        () => tapWorld(tester, standardSpot(3)), // tap 1B = the throw
        // The throw arrived at first with the batter heading there: the
        // SAFE/OUT pair is up at the bag — OUT resolves the force play.
        () => tapPill(tester, 1, out: true),
        () => tapKey(tester, fieldCommitKey),
      ]);

      final events = await stream();
      final tail = events.sublist(events.length - 5);
      expect(tail.map((e) => e.type), [
        'BallInPlay',
        'FielderTouch',
        'FielderTouch',
        'FielderTouch',
        'RunnerOut',
      ]);
      expect(tail[0].payload['landingIsCaught'], isFalse);
      final landing = tail[0].payload['landing'] as Map<String, dynamic>;
      expect(landing['x'] as double, closeTo(-45, 2));
      expect(tail[1].payload['touchType'], 'dropped');
      expect(tail[1].payload['position'], 6);
      expect(tail[1].payload['anchorEventId'], tail[0].id);
      expect(tail[2].payload['touchType'], 'fielded');
      expect(tail[3].payload['touchType'], 'received_throw');
      expect(tail[3].payload['position'], 3);
      expect(tail[4].payload['how'], 'force');
      expect(tail[4].payload['putoutTouchId'], tail[3].id);
      expect(container.read(gameControllerProvider).value!.outs, 1);
    });

    testWidgets('play 02 — boot then throw-away, batter to third: 11 field '
        'gestures', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      final spot = FieldCoord(x: -50, y: 95);

      // Eleven. v0.56 stopped the boot from claiming her reach, and this
      // play carries *two* errors — the boot put her on first, the throw
      // gave her second and third — so the scorer names each on the leg it
      // caused instead of the app picking one misplay for all three bases.
      // Those two taps are the point of the ticket. Against them, the boot
      // no longer needs a "she picked it up" tap, and marking the throw
      // wild takes the reception off rather than leaving 1B credited with
      // catching a ball that sailed past her.
      await runGestures(11, [
        () => tapKey(tester, trajectoryKey(Trajectory.GROUND)),
        () => dragFielder(tester, 6, spot),
        () => tapKey(tester, fielderPlayKey('booted')),
        () => tapWorld(tester, standardSpot(3)), // the throw to first
        // Key 3: the throw minted her recovery (key 2) and then the
        // reception, so the reception is the node after it.
        () => tapKey(tester, chainNodeKey(3)),
        () => tapKey(tester, chainChipKey('throw_was_wild')),
        () => dragToken(tester, 1, 3, originFrom: 0),
        () => tapKey(tester, safeChipKey('error-throwing-6')),
        () => tapKey(tester, safeChipKey('earned-0')), // she earned none
        () => tapKey(tester, fieldCommitKey), // ✓ asks who put her on first
        () => tapKey(tester, safeChipKey('error-fielding-6')),
      ]);

      final events = await stream();
      final tail = events.sublist(events.length - 5);
      expect(tail.map((e) => e.type), [
        'BallInPlay',
        'FielderTouch',
        'RunnerAdvance',
        'FielderTouch',
        'RunnerAdvance',
      ]);
      expect(tail[1].payload['touchType'], 'booted');
      expect(tail[2].payload['reason'], 'error');
      expect(tail[2].payload['enabledByTouchId'], tail[1].id);
      expect(tail[2].payload['from'], 0);
      expect(tail[2].payload['to'], 1);
      expect(tail[3].payload['touchType'], 'wild_throw');
      expect(tail[4].payload['reason'], 'wild_throw');
      expect(tail[4].payload['enabledByTouchId'], tail[3].id);
      expect(tail[4].payload['from'], 1);
      expect(tail[4].payload['to'], 3);
      expect(
        container.read(gameControllerProvider).value!.bases.third,
        'opp-1',
      );
    });

    testWidgets('play 03 — single, R3 scores, batter out stretching 9-6: '
        '9 field gestures', (tester) async {
      await pumpLoop(tester);
      // Setup: a runner on third (the play found her there).
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r3',
              from: 0,
              to: 3,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);
      final spot = FieldCoord(x: 110, y: 180);

      await runGestures(9, [
        () => tapKey(tester, trajectoryKey(Trajectory.LINE)),
        () => dragFielder(tester, 9, spot),
        () => tapKey(tester, fielderPlayKey('fielded')),
        () => dragToken(tester, 3, 4, target: 'base'), // R3 home
        () => tapKey(tester, safeChipKey('hit')),
        () => dragBall(tester, spot, standardSpot(6)), // the 9-6 throw
        () => dragToken(tester, 1, 2, target: 'out', originFrom: 0),
        () => tapKey(tester, outChipKey('tag')),
        () => tapKey(tester, fieldCommitKey),
      ]);

      final events = await stream();
      final tail = events.sublist(events.length - 8);
      expect(tail.map((e) => e.type), [
        'PitchThrown',
        'BallInPlay',
        'RunnerAdvance', // the batter's walk-up, clean → batted_ball
        'FielderTouch', // 9 fielded, located at the play
        'RunnerAdvance', // r3 scores
        'FielderTouch', // 6 received_throw
        'FielderTouch', // 6 tag_applied (auto)
        'RunnerOut', // tag at second
      ]);
      expect(tail[2].payload['runnerId'], 'opp-1');
      expect(tail[2].payload['to'], 1);
      expect(tail[2].payload['reason'], 'batted_ball');
      expect(tail[3].payload['touchType'], 'fielded');
      expect(tail[3].payload['position'], 9);
      final location = tail[3].payload['location'] as Map<String, dynamic>;
      expect(location['x'] as double, closeTo(110, 2));
      expect(tail[4].payload['runnerId'], 'r3');
      expect(tail[4].payload['to'], 4);
      expect(tail[5].payload['touchType'], 'received_throw');
      expect(tail[6].payload['touchType'], 'tag_applied');
      expect(tail[6].payload['position'], 6);
      expect(tail[7].payload['how'], 'tag');
      expect(tail[7].payload['atBase'], 2);
      expect(tail[7].payload['putoutTouchId'], tail[6].id);

      final state = container.read(gameControllerProvider).value!;
      expect(state.outs, 1);
      expect(state.runsByTeam['opp'], 1);
      expect(state.bases.first, isNull);
    });
  });

  group('the OUT menu offers only possible outs (§4.3)', () {
    /// Puts [runnerId] on [base] before the play, as the fold sees it.
    Future<void> placeRunner(String runnerId, int base) async {
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: runnerId,
              from: 0,
              to: base,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
    }

    testWidgets('runner from second with first empty is forced nowhere: '
        'thrown out at home, she was tagged', (tester) async {
      await pumpLoop(tester);
      await placeRunner('r2', 2); // the leadoff double
      await tester.pumpAndSettle();
      await reachFieldSurface(tester); // the single behind her

      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      await tapWorld(tester, FieldCoord(x: 60, y: 150));
      await dragToken(tester, 2, 4, target: 'out');

      expect(find.text('Force'), findsNothing);
      expect(find.text('Tag'), findsOneWidget);
      await tapKey(tester, outChipKey('tag'));
      await tapKey(tester, fieldCommitKey);

      final out = (await stream()).lastWhere((e) => e.type == 'RunnerOut');
      expect(out.payload['how'], 'tag');
      expect(out.payload['atBase'], 4);
    });

    testWidgets('bases loaded, the runner from third IS forced at home', (
      tester,
    ) async {
      await pumpLoop(tester);
      await placeRunner('r1', 1);
      await placeRunner('r2', 2);
      await placeRunner('r3', 3);
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);

      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: 0, y: 60));
      await dragToken(tester, 4, 4, target: 'out', originFrom: 3);

      expect(find.text('Force'), findsOneWidget);
      await tapKey(tester, outChipKey('force'));
      await tapKey(tester, fieldCommitKey);

      final out = (await stream()).lastWhere((e) => e.type == 'RunnerOut');
      expect(out.payload['how'], 'force');
      expect(out.payload['runnerId'], 'r3');
    });

    testWidgets('a catch removes every force — the runner owes a retouch, '
        'not an advance', (tester) async {
      await pumpLoop(tester);
      await placeRunner('r1', 1);
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);

      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('caught'));

      await dragToken(tester, 1, 1, target: 'out');
      expect(find.text('Force'), findsNothing);
      expect(find.text("Didn't tag up"), findsOneWidget);
    });

    testWidgets('fly out belongs to the batter; the appeal does not', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('dropped')); // she can still run

      await dragToken(tester, 1, 2, target: 'out', originFrom: 0);
      expect(find.text('Fly out'), findsNothing, reason: 'nothing was caught');
      expect(find.text('Force'), findsNothing, reason: 'second is not next');
      expect(find.text('Tag'), findsOneWidget);
    });
  });

  group('the catch and its appeal (§15.1 v0.43)', () {
    testWidgets('a caught fly returns runners to their bases; the OUT '
        'dialog then offers the tag-up appeal', (tester) async {
      await pumpLoop(tester);
      // A runner on second, so there is somebody to double off.
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r2',
              from: 0,
              to: 2,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);

      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('caught'));

      // She never tagged: the throw goes to second, then she's doubled off.
      await tapWorld(tester, standardSpot(6));
      await dragToken(tester, 2, 2, target: 'out');
      expect(find.text("Didn't tag up"), findsOneWidget);
      await tapKey(tester, outChipKey('appeal'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final outs = events.where((e) => e.type == 'RunnerOut').toList();
      expect(outs, hasLength(2));
      expect(outs.first.payload['how'], 'fly_out');
      expect(outs.last.payload['runnerId'], 'r2');
      expect(outs.last.payload['how'], 'appeal');
      expect(outs.last.payload['atBase'], 2);
      // The putout goes to whoever held the ball at the bag.
      final received = events.lastWhere(
        (e) =>
            e.type == 'FielderTouch' &&
            e.payload['touchType'] == 'received_throw',
      );
      expect(outs.last.payload['putoutTouchId'], received.id);
      expect(container.read(gameControllerProvider).value!.outs, 2);
    });

    testWidgets('with two away the catch is the third out: no OUT pill, no '
        'appeal, no fourth out (§4.4)', (tester) async {
      await pumpLoop(tester);
      final game = container.read(gameControllerProvider.notifier);
      for (final id in ['x1', 'x2']) {
        await game.append(
          type: 'RunnerOut',
          payload: RunnerOut(runnerId: id, atBase: 1, how: How.FORCE).toJson(),
        );
      }
      await game.append(
        type: 'RunnerAdvance',
        payload: RunnerAdvance(
          runnerId: 'r2',
          from: 0,
          to: 2,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ).toJson(),
      );
      await tester.pumpAndSettle();
      expect(container.read(gameControllerProvider).value!.outs, 2);

      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('caught')); // the third out

      // The half is over: dragging the runner onto OUT does nothing.
      await dragToken(tester, 2, 2, target: 'out');
      expect(find.text("Didn't tag up"), findsNothing);
      expect(find.text('Tag'), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final state = container.read(gameControllerProvider).value!;
      expect(state.outs, 3, reason: 'never a fourth');
      expect(state.halfEnded, isTrue);
      final outs = (await stream()).where((e) => e.type == 'RunnerOut');
      expect(outs, hasLength(3));
    });

    testWidgets('with one away the appeal still stands — doubled off for '
        'the third out', (tester) async {
      await pumpLoop(tester);
      final game = container.read(gameControllerProvider.notifier);
      await game.append(
        type: 'RunnerOut',
        payload: RunnerOut(runnerId: 'x1', atBase: 1, how: How.FORCE).toJson(),
      );
      await game.append(
        type: 'RunnerAdvance',
        payload: RunnerAdvance(
          runnerId: 'r2',
          from: 0,
          to: 2,
          reason: RunnerAdvanceReason.BATTED_BALL,
        ).toJson(),
      );
      await tester.pumpAndSettle();

      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 20, y: 170));
      await tapKey(tester, fielderPlayKey('caught')); // the second out

      await dragToken(tester, 2, 2, target: 'out');
      expect(find.text("Didn't tag up"), findsOneWidget);
      await tapKey(tester, outChipKey('appeal'));
      await tapKey(tester, fieldCommitKey);

      final state = container.read(gameControllerProvider).value!;
      expect(state.outs, 3);
      expect(state.halfEnded, isTrue);
    });

    testWidgets('with no catch, the appeal is not offered', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await dragToken(tester, 1, 2, target: 'out', originFrom: 0);
      expect(find.text("Didn't tag up"), findsNothing);
      expect(find.text('Tag'), findsOneWidget);
    });
  });

  group('the SAFE menu after a catch (§15.1 v0.43)', () {
    Future<void> flyBallWithRunnerOnThird(WidgetTester tester) async {
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r3',
              from: 0,
              to: 3,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 10, y: 200));
      await tapKey(tester, fielderPlayKey('caught'));
    }

    testWidgets('a runner tagging home on a caught fly with no throw is not '
        'asked at all — one possible answer is not a question', (tester) async {
      await pumpLoop(tester);
      await flyBallWithRunnerOnThird(tester);

      await dragToken(tester, 3, 4, target: 'base');
      // No popup: nothing else could have moved her.
      expect(find.text('On the hit'), findsNothing);
      expect(find.text("Fielder's choice"), findsNothing);
      expect(find.text('Obstruction'), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.runnerId, 'r3');
      expect(advance.from, 3);
      expect(advance.to, 4);
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
      // Which is exactly the shape §13.6 reads as a sacrifice fly.
      expect(
        container.read(gameControllerProvider).value!.runsByTeam['opp'],
        1,
      );
    });

    testWidgets('with a throw it asks, and says tagged up rather than "on '
        'the hit" — nothing was hit anywhere', (tester) async {
      await pumpLoop(tester);
      await flyBallWithRunnerOnThird(tester);
      await tapWorld(tester, standardSpot(2)); // the throw home

      await dragToken(tester, 3, 4, target: 'base');
      expect(find.text('Tagged up'), findsOneWidget);
      expect(find.text('On the hit'), findsNothing);
      expect(find.text('On the throw'), findsOneWidget);
      expect(find.text("Fielder's choice"), findsNothing);
      await tapKey(tester, safeChipKey('hit'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
    });

    testWidgets('"On the throw" needs a throw, not merely a touch', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -40, y: 90));
      await tapKey(tester, fielderPlayKey('fielded'));

      await dragToken(tester, 1, 2, originFrom: 0);
      expect(find.text('On the throw'), findsNothing);
      // The batter's own answer names the hit she got.
      expect(find.text('Double'), findsOneWidget);
    });
  });

  group('the SAFE menu offers only answers with a cause (§13.2)', () {
    testWidgets('"On an error" is absent until a misplay exists to link', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded')); // clean

      await dragToken(tester, 1, 2, originFrom: 0);
      expect(find.text('On an error'), findsNothing);
      await tapKey(tester, safeChipKey('hit'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final advance = RunnerAdvance.fromJson(events.last.payload);
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
    });

    testWidgets('with a misplay on the chain it is offered, and links to it', (
      tester,
    ) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('booted'));

      await dragToken(tester, 1, 2, originFrom: 0);
      // Named, not generic: the scorer charges the boot, not "an error".
      expect(find.text('On the fielding error'), findsOneWidget);
      await tapKey(tester, safeChipKey('error-fielding-6'));
      // How the bases divide is the second question (§13.2 v0.56): none of
      // them earned, so both legs link to the boot.
      expect(find.text('Single and an error'), findsOneWidget);
      await tapKey(tester, safeChipKey('earned-0'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.firstWhere((e) => e.type == 'FielderTouch');
      final advance = events.lastWhere((e) => e.type == 'RunnerAdvance');
      expect(advance.payload['enabledByTouchId'], touch.id);
      expect(advance.payload['reason'], 'error');
    });

    testWidgets('the earned breakdown splits the dragged leg: a double, then '
        'third on the boot (§13.2 v0.56)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('booted'));

      await dragToken(tester, 1, 3, originFrom: 0);
      await tapKey(tester, safeChipKey('error-fielding-6'));
      // Mark's wording: the hit she earned, then the error that gave her
      // the rest. One base given reads "and an error"; two reads "2 base".
      expect(find.text('Double and an error'), findsOneWidget);
      expect(find.text('Single, 2 base error'), findsOneWidget);
      expect(find.text('3 base error'), findsOneWidget);
      await tapKey(tester, safeChipKey('earned-2'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.firstWhere((e) => e.type == 'FielderTouch');
      final legs = events.where((e) => e.type == 'RunnerAdvance').toList();
      // Three legs, because three separate things are true: she earned
      // first, she earned second, and the boot gave her third.
      expect(legs, hasLength(3));
      expect(legs.map((e) => (e.payload['from'], e.payload['to'])), [
        (0, 1),
        (1, 2),
        (2, 3),
      ]);
      expect(legs[0].payload['enabledByTouchId'], isNull);
      expect(legs[1].payload['enabledByTouchId'], isNull);
      expect(legs[2].payload['enabledByTouchId'], touch.id);
      expect(legs[2].payload['reason'], 'error');
    });

    testWidgets('two misplays: earning nothing is two errors, not one of '
        'three bases (§13.2 v0.56)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      final spot = FieldCoord(x: -50, y: 95);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, spot);
      await tapKey(tester, fielderPlayKey('booted')); // key 1
      // The throw mints her recovery (key 2) and the reception (key 3);
      // marking it wild retypes the recovery and takes the reception off.
      await tapWorld(tester, standardSpot(3));
      await tapKey(tester, chainNodeKey(3));
      await tapKey(tester, chainChipKey('throw_was_wild'));

      await dragToken(tester, 1, 3, originFrom: 0);
      // Both errors are on offer by name; the throw is what gave her these
      // bases, so that is the one charged for them.
      expect(find.text('On the fielding error'), findsOneWidget);
      expect(find.text('On the throwing error'), findsOneWidget);
      await tapKey(tester, safeChipKey('error-throwing-6'));
      // The play reads as two errors — "reached first on a fielding error by
      // SS; reached third on a two base throwing error by SS" — so earning
      // nothing here says nothing about the reach, and a "3 base error" chip
      // would state a count that was never one error.
      expect(find.text('None of it earned'), findsOneWidget);
      expect(find.text('3 base error'), findsNothing);
      await tapKey(tester, safeChipKey('earned-0'));
      // The reach is still open on purpose: the ✓ asks who put her on first.
      await tapKey(tester, fieldCommitKey);
      await tapKey(tester, safeChipKey('error-fielding-6'));

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      final boot = touches.first;
      final wild = touches.last;
      expect(boot.payload['touchType'], 'booted');
      expect(wild.payload['touchType'], 'wild_throw');
      final legs = events.where((e) => e.type == 'RunnerAdvance').toList();
      expect(legs, hasLength(2));
      // Each base is charged to the misplay that actually gave it.
      expect(legs[0].payload['enabledByTouchId'], boot.id);
      expect((legs[0].payload['from'], legs[0].payload['to']), (0, 1));
      expect(legs[1].payload['enabledByTouchId'], wild.id);
      expect((legs[1].payload['from'], legs[1].payload['to']), (1, 3));
    });

    testWidgets('the breakdown is offered after the reach is settled too, '
        'and stops at the base she stands on (§13.2 v0.56)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      final spot = FieldCoord(x: -50, y: 95);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, spot);
      await tapKey(tester, fielderPlayKey('booted'));
      await tapWorld(tester, standardSpot(3)); // the throw to first
      // She beat it out: the reach is settled as a hit, right here.
      await tapPill(tester, 1);
      await tapKey(tester, safeChipKey('hit'));

      // Now she takes third on the same boot. The breakdown still opens —
      // dividing those bases is a question whether or not the reach was
      // open — but "she earned none of it" is gone, because she has already
      // been credited the single it would contradict.
      // No originFrom: she is standing on first now, not running to it.
      await dragToken(tester, 1, 3);
      await tapKey(tester, safeChipKey('error-fielding-6'));
      expect(find.text('Double and an error'), findsOneWidget);
      expect(find.text('Single, 2 base error'), findsOneWidget);
      expect(find.text('3 base error'), findsNothing);
      expect(find.text('None of it earned'), findsNothing);

      await tapKey(tester, safeChipKey('earned-2'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final boot = events.firstWhere((e) => e.type == 'FielderTouch');
      final legs = events.where((e) => e.type == 'RunnerAdvance').toList();
      expect(legs.map((e) => (e.payload['from'], e.payload['to'])), [
        (0, 1),
        (1, 2),
        (2, 3),
      ]);
      expect(legs[0].payload['enabledByTouchId'], isNull); // the single
      expect(legs[1].payload['enabledByTouchId'], isNull); // earned second
      expect(legs[2].payload['enabledByTouchId'], boot.id); // third on the boot
    });

    testWidgets('a runner already aboard gets no breakdown — she has no hit '
        'to divide (§13.2 v0.56)', (tester) async {
      await pumpLoop(tester);
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r1',
              from: 0,
              to: 1,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('booted'));

      // The batter's walk-up already forced R1 to second, so she is running
      // there; the boot then sends her on to third. Naming the error is the
      // whole answer — no "double and an error" ladder, which would describe
      // a hit she never took.
      await dragToken(tester, 2, 3, originFrom: 1);
      await tapKey(tester, safeChipKey('error-fielding-6'));
      expect(find.text('How much did she earn?'), findsNothing);

      // The batter's own reach is still open, so the ✓ asks it — hers is
      // the only hit on the play to divide.
      await tapKey(tester, fieldCommitKey);
      await tapKey(tester, safeChipKey('error-fielding-6'));

      final events = await stream();
      final boot = events.firstWhere((e) => e.type == 'FielderTouch');
      final legs = events.where((e) => e.type == 'RunnerAdvance').toList();
      // Last, not first: the setup advance that put her on first is in the
      // stream too.
      final r1Leg = legs.lastWhere((e) => e.payload['runnerId'] == 'r1');
      // One leg, linked whole: no split, no hit rank invented for her.
      expect((r1Leg.payload['from'], r1Leg.payload['to']), (2, 3));
      expect(r1Leg.payload['enabledByTouchId'], boot.id);
    });

    testWidgets('SAFE on the force play asks what the boot cost — it no '
        'longer settles her silently (§13.2 v0.56)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('booted'));
      await tapWorld(tester, standardSpot(3)); // the throw to first

      // Affirming alone would commit a plain unattributed reach, which
      // derives a *hit* — the boot swallowed in the other direction.
      await tapPill(tester, 1);
      expect(find.text('Safe at 1B — how?'), findsOneWidget);
      await tapKey(tester, safeChipKey('error-fielding-6'));
      // Answered here, so the ✓ has nothing left to ask and commits.
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final boot = events.firstWhere((e) => e.type == 'FielderTouch');
      expect(boot.payload['touchType'], 'booted');
      final advance = events.lastWhere((e) => e.type == 'RunnerAdvance');
      expect(advance.payload['enabledByTouchId'], boot.id);
      expect(advance.payload['reason'], 'error');
    });

    testWidgets('answering Single leaves the hit standing and charges the '
        'boot nothing (§13.2 v0.56)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('booted'));

      // Nobody touched her, so the ✓ is where the question surfaces.
      await tapKey(tester, fieldCommitKey);
      expect(find.text('Safe at 1B — how?'), findsOneWidget);
      await tapKey(tester, safeChipKey('hit'));

      final events = await stream();
      final advance = events.lastWhere((e) => e.type == 'RunnerAdvance');
      expect(advance.payload['enabledByTouchId'], isNull);
      expect(advance.payload['reason'], 'batted_ball');
      // The misplay stays on the record; it simply cost nothing.
      final touch = events.firstWhere((e) => e.type == 'FielderTouch');
      expect(touch.payload['touchType'], 'booted');
    });
  });

  group('the ball and the fielder are one fact (§15.1)', () {
    testWidgets('tapping a fielder puts her on the ball, not at her post', (
      tester,
    ) async {
      // Trace a ball into the left-field corner, then tap the left fielder.
      // She fielded it *there* — her touch used to record her standing spot,
      // a place the ball had never been, and that location is the one
      // official scoring reads.
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      await tapWorld(tester, FieldCoord(x: -60, y: 120));
      await tapWorld(tester, FieldCoord(x: -110, y: 150));

      await tapWorld(
        tester,
        standardFielderSpots(FieldProfile.fastpitch12U)[7]!,
      );
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events
          .map(
            (e) => e.type == 'FielderTouch'
                ? FielderTouch.fromJson(e.payload)
                : null,
          )
          .whereType<FielderTouch>()
          .single;
      expect(touch.position, 7);
      expect(touch.location, isNotNull);
      expect(touch.location!.x, closeTo(-110, 2));
      expect(touch.location!.y, closeTo(150, 2));
    });
  });

  group('the sacrifice judgment (§13.6 v0.43)', () {
    testWidgets('a bunt that moves a runner offers the judgment; a bunt that '
        'moves nobody does not', (tester) async {
      await pumpLoop(tester);
      await container
          .read(gameControllerProvider.notifier)
          .append(
            type: 'RunnerAdvance',
            payload: RunnerAdvance(
              runnerId: 'r1',
              from: 0,
              to: 1,
              reason: RunnerAdvanceReason.BATTED_BALL,
            ).toJson(),
          );
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);

      await tapKey(tester, trajectoryKey(Trajectory.BUNT));
      await tapWorld(tester, FieldCoord(x: -18, y: 24));
      // The walk-up pushed R1 to second, so the question is live.
      expect(find.byKey(sacrificeChipKey), findsOneWidget);
      await tapKey(tester, sacrificeChipKey);

      // She is thrown out at first; the runner she moved stands at second.
      await tapWorld(tester, standardSpot(5));
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapWorld(tester, standardSpot(3));
      await tapPill(tester, 1, out: true);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.sacrifice, isTrue);
      expect(ball.trajectory, Trajectory.BUNT);
    });

    testWidgets('no runner moved, no question — a bunt for a hit is just a '
        'bunt', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.BUNT));
      await tapWorld(tester, FieldCoord(x: -18, y: 24));
      expect(find.byKey(sacrificeChipKey), findsNothing);
    });

    testWidgets('a fly with nobody scoring does not ask', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await tapWorld(tester, FieldCoord(x: 0, y: 180));
      expect(find.byKey(sacrificeChipKey), findsNothing);
    });
  });

  group('the locked path and the reset (§15.1 v0.43)', () {
    testWidgets('once anything hangs off the path, open-field taps stop '
        'changing it; ↺ starts the play over', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -60, y: 140));
      expect(find.text('152 ft'), findsOneWidget);

      // A fielder plays it: the path is now load-bearing.
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded'));

      // Open-field taps no longer touch the streak.
      await tapWorld(tester, FieldCoord(x: -85, y: 190));
      expect(find.text('152 ft'), findsOneWidget);

      // Stepping back to the start wipes the play — trajectory question and
      // all — and the path draws fresh. The ↺ that used to do this in one
      // tap is gone (§15.2 v0.54): undo is one button in the top bar, and
      // starting over is undoing to the bottom of the stack.
      for (var i = 0; i < 6; i++) {
        if (find.text('How did it come off the bat?').evaluate().isNotEmpty) {
          break;
        }
        await tapKey(tester, countHudUndoKey);
      }
      expect(find.text('How did it come off the bat?'), findsOneWidget);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await tapWorld(tester, FieldCoord(x: 30, y: 160));
      expect(find.text('163 ft'), findsOneWidget); // √(30²+160²)

      await tapKey(tester, fieldCommitKey);
      final events = await stream();
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.trajectory, Trajectory.FLY);
      expect(ball.landing.x, closeTo(30, 2));
      expect(events.map((e) => e.type), isNot(contains('FielderTouch')));
    });

    testWidgets('re-dragging a fielder who already played the ball adjusts '
        'her play — one touch, moved, never two', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.FLY));
      await dragFielder(tester, 8, FieldCoord(x: 30, y: 160));
      await tapKey(tester, fielderPlayKey('caught'));

      // Second thought: she actually caught it deeper toward the gap. The
      // re-drag moves her and the play — no popup, no second touch.
      await drag(
        tester,
        worldPx(tester, FieldCoord(x: 30, y: 160)),
        worldPx(tester, FieldCoord(x: 55, y: 175)),
      );
      expect(find.byKey(fielderPlayKey('caught')), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      expect(touches, hasLength(1));
      final location =
          touches.single.payload['location'] as Map<String, dynamic>;
      expect(location['x'] as double, closeTo(55, 2));
      final ball = BallInPlay.fromJson(
        events.lastWhere((e) => e.type == 'BallInPlay').payload,
      );
      expect(ball.landing.x, closeTo(55, 2), reason: 'assumed landing moves');
    });
  });

  group('chips and prompts (§15.3–15.4)', () {
    testWidgets('a throw to first never guesses at a drop: SAFE offers the '
        'vocabulary and volunteers nothing', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapWorld(tester, standardSpot(3)); // the throw

      // Nothing is volunteered: no chip suggests a drop before she is
      // asked about, which is §15.4's withdrawn first-base prompt staying
      // withdrawn.
      expect(find.textContaining('rop'), findsNothing);
      await tapPill(tester, 1);
      // v0.56: SAFE asks the same question the drag does, and the routine
      // answer leads. "Dropped the throw" is *offered* here — that is the
      // point, since it was previously reachable only from the chain strip
      // — but offering an answer is not guessing at one, and taking the
      // hit leaves the record exactly as it was before.
      expect(find.text('Dropped the throw'), findsOneWidget);
      await tapKey(tester, safeChipKey('hit'));
      expect(find.textContaining('rop'), findsNothing);
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      expect(touch.payload['touchType'], 'received_throw');
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.BATTED_BALL);
      expect(advance.to, 1);
    });

    testWidgets('the drop is still one tap when it happened — on the node '
        'that took the throw', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded')); // key 1
      await tapWorld(tester, standardSpot(3)); // key 2, the throw
      await tapPill(tester, 1); // safe
      // v0.56: the pill asks the same question the drag does.
      await tapKey(tester, safeChipKey('hit'));

      await tapKey(tester, chainNodeKey(2));
      await tapKey(tester, chainChipKey('dropped'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      expect(touch.payload['touchType'], 'dropped');
      expect(touch.payload['position'], 3);
    });

    testWidgets('bases loaded, throw home, the throw was wild: enterable '
        'from the SAFE pill, no trip to the chain strip (§15.1 v0.56)', (
      tester,
    ) async {
      await pumpLoop(tester);
      for (final (id, base) in [('r1', 1), ('r2', 2), ('r3', 3)]) {
        await container
            .read(gameControllerProvider.notifier)
            .append(
              type: 'RunnerAdvance',
              payload: RunnerAdvance(
                runnerId: id,
                from: 0,
                to: base,
                reason: RunnerAdvanceReason.BATTED_BALL,
              ).toJson(),
            );
      }
      await tester.pumpAndSettle();
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded'));
      await tapWorld(tester, standardSpot(2)); // the throw home

      // The force play at the plate. Before v0.56 SAFE settled R3 silently
      // as batted-ball movement: an earned run, an RBI, and no error, with
      // the throw's story reachable only from the chain strip.
      await tapPill(tester, 4);
      await tapKey(tester, safeChipKey('wild_throw'));
      await tapKey(tester, fieldCommitKey);
      await tapKey(tester, safeChipKey('error-throwing-6'));

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      // SS threw it away; the catcher is not credited with receiving it.
      expect(touches.map((e) => e.payload['touchType']), ['wild_throw']);
      expect(touches.single.payload['position'], 6);
      final home = events.lastWhere(
        (e) => e.type == 'RunnerAdvance' && e.payload['runnerId'] == 'r3',
      );
      expect(home.payload['to'], 4);
      expect(home.payload['enabledByTouchId'], touches.single.id);
      // A leg off a wild throw keeps that as its reason (§14 play-02 does
      // the same); the charge comes from the link, not the word.
      expect(home.payload['reason'], 'wild_throw');
    });

    testWidgets('marking a throw wild takes the reception off — nobody '
        'receives a wild throw (§15.3 v0.56)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded')); // key 1
      await tapWorld(tester, standardSpot(3)); // key 2, the throw
      expect(find.byKey(chainNodeKey(2)), findsOneWidget);

      await tapKey(tester, chainNodeKey(2));
      await tapKey(tester, chainChipKey('throw_was_wild'));
      // The reception is gone from the chain, not merely retyped.
      expect(find.byKey(chainNodeKey(2)), findsNothing);

      await tapKey(tester, fieldCommitKey);
      await tapKey(tester, safeChipKey('error-throwing-6'));

      final events = await stream();
      final touches = events.where((e) => e.type == 'FielderTouch').toList();
      // One touch by one fielder: her pickup *became* the wild throw (the
      // chip retypes the thrower, which is what §14 play-02's own encoding
      // shows), and 1B is not credited with catching a ball that sailed
      // past her.
      expect(touches, hasLength(1));
      expect(touches.single.payload['touchType'], 'wild_throw');
      expect(touches.single.payload['position'], 6);
    });

    testWidgets('arrival quality on a receiving node: underline info, '
        'never official scoring (§15.3)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await tapWorld(tester, standardSpot(6));
      await tapKey(tester, fielderPlayKey('fielded')); // entry key 1
      await tapWorld(tester, standardSpot(3)); // tap = throw, key 2
      await tapPill(tester, 1); // SAFE — the throw's story comes next
      // v0.56: the pill asks the same question the drag does.
      await tapKey(tester, safeChipKey('hit'));

      await tapKey(tester, chainNodeKey(2));
      await tapKey(tester, chainChipKey('short_hop'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      expect(touch.payload['receivedQuality'], 'short_hop');
      expect(touch.payload['touchType'], 'received_throw');
    });

    testWidgets('fixture 02 variant, v0.56: the boot she beat out is the '
        'link left unmade, not a switch flipped', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -50, y: 95));
      await tapKey(tester, fielderPlayKey('booted')); // key 1
      // There is no ordinary-effort switch on the node any more: the whole
      // judgment is which answer she gives here.
      await tapKey(tester, fieldCommitKey);
      expect(find.text('Ordinary effort?'), findsNothing);
      await tapKey(tester, safeChipKey('hit'));

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      expect(touch.payload['touchType'], 'booted');
      expect(touch.payload.containsKey('ordinaryEffort'), isFalse);
      // The misplay is on the record and charges nothing, because she says
      // she beat it out — the pair the flag could never express.
      final advance = events.lastWhere((e) => e.type == 'RunnerAdvance');
      expect(advance.payload['enabledByTouchId'], isNull);
      expect(advance.payload['reason'], 'batted_ball');
    });

    testWidgets('a ⚖ on the runner consequence: obstruction inserts before '
        'the advance and links it (§15.3 v0.43)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.LINE));
      await tapWorld(tester, FieldCoord(x: -45, y: 120));
      await dragToken(tester, 1, 2, originFrom: 0); // batter 1B → 2B
      // Not on the first-pass menu: a ⚖ is a correction, found on the node.
      expect(find.text('Obstruction'), findsNothing);
      await tapKey(tester, safeChipKey('hit'));

      await tapKey(tester, chainNodeKey(1)); // the leg she just took
      await tapKey(tester, chainChipKey('obstruction'));
      // The call names a fielder — obstruction is charged to her (§13.2).
      expect(find.text('Obstructed by?'), findsOneWidget);
      await tapKey(tester, positionPickKey(6));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final types = events.map((e) => e.type).toList();
      expect(types, containsAllInOrder(['RuleCall', 'RunnerAdvance']));
      final call = events.lastWhere((e) => e.type == 'RuleCall');
      expect(call.payload['callType'], 'obstruction');
      expect(call.payload['againstPosition'], 6);
      final advance = events.lastWhere((e) => e.type == 'RunnerAdvance');
      expect(advance.payload['reason'], 'obstruction');
      expect(advance.payload['to'], 2);
      // The link survives commit, not just the reason it implies.
      expect(advance.payload['enabledByCallId'], call.id);
    });
  });

  group('interference is the out-flavored ⚖ (§15.1 v0.43)', () {
    testWidgets('OUT popup: Interference inserts the call and the how '
        'becomes interference', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: -50, y: 95));
      await dragToken(tester, 1, 2, target: 'out', originFrom: 0);
      expect(find.text('Interference'), findsNothing);
      await tapKey(tester, outChipKey('tag'));

      await tapKey(tester, chainNodeKey(1)); // the out just recorded
      await tapKey(tester, chainChipKey('interference_runner'));
      expect(find.text('Interfered with?'), findsOneWidget);
      await tapKey(tester, positionPickKey(4));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      expect(
        events.map((e) => e.type).toList(),
        containsAllInOrder(['RuleCall', 'RunnerOut']),
      );
      final call = events.lastWhere((e) => e.type == 'RuleCall');
      expect(call.payload['callType'], 'interference_runner');
      expect(call.payload['againstPosition'], 4);
      final out = events.lastWhere((e) => e.type == 'RunnerOut');
      expect(out.payload['how'], 'interference');
      expect(out.payload['atBase'], 2);
      expect(out.payload['enabledByCallId'], call.id);
    });
  });

  group('discard and restore (§15.5)', () {
    testWidgets('cancel starts the play over and never strands the pitch', (
      tester,
    ) async {
      // This used to assert that ✕ abandoned the play and left the pitch —
      // an `in_play` pitch with no play recorded, which is an incomplete
      // record the scorer could reach in one tap. Cancel now restarts the
      // play in place (Mark, 2026-09-01), so that state is unreachable:
      // leaving the field is undo's job, and undo takes the pitch with it.
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await tapWorld(tester, FieldCoord(x: 0, y: 100));
      await tapKey(tester, countHudCancelKey);

      expect(find.byKey(fieldCanvasKey), findsOneWidget, reason: 'still here');
      expect(find.text('How did it come off the bat?'), findsOneWidget);
      final types = (await stream()).map((e) => e.type).toList();
      expect(types, contains('PitchThrown'));
      expect(
        types,
        isNot(contains('BallInPlay')),
        reason: '§15.5: nothing enters the stream until commit',
      );
    });

    testWidgets('kill mid-play, relaunch: trajectory, ball, chain, and '
        'moved fielders restore (DIA-008 accept)', (tester) async {
      await pumpLoop(tester);
      await reachFieldSurface(tester);
      await tapKey(tester, trajectoryKey(Trajectory.GROUND));
      await dragFielder(tester, 6, FieldCoord(x: -45, y: 120));
      await tapKey(tester, fielderPlayKey('booted'));

      // "Kill the app": tear the widget tree down and relaunch on a fresh
      // container — only the database survives, exactly like a real death.
      // (The first container is merely abandoned; tearDown disposes it.)
      await tester.pumpWidget(const SizedBox());

      final second = relaunch();
      await pumpLoop(tester, into: second);

      expect(find.byKey(fieldCanvasKey), findsOneWidget);
      expect(find.text('128 ft'), findsOneWidget); // the assumed landing
      expect(find.text('Grounder'), findsOneWidget); // the header chip
      // Restored with a trajectory: no modal re-asks.
      expect(find.text('How did it come off the bat?'), findsNothing);
      expect(find.byKey(chainNodeKey(1)), findsOneWidget); // the boot node

      // And the restored draft still commits, location and reach intact —
      // the ✓ asking what the boot cost, since the draft came back with the
      // question still open (§13.2 v0.56).
      await tapKey(tester, fieldCommitKey);
      await tapKey(tester, safeChipKey('error-fielding-6'));
      final events = await stream(from: second);
      expect(events.last.type, 'RunnerAdvance'); // the claimed reach
      expect(events.last.payload['reason'], 'error');
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      final location = touch.payload['location'] as Map<String, dynamic>;
      expect(location['x'] as double, closeTo(-45, 2));
    });
  });

  group('the idle field (§15.6 v0.42) — between-pitch runner events', () {
    /// Walk opp-1 aboard, then open the field with nothing in play.
    Future<void> runnerOnFirstThenField(WidgetTester tester) async {
      await pumpLoop(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Skip call'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Skip location'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ball'));
        await tester.pumpAndSettle();
      }
      await tapKey(tester, openIdleFieldKey);
    }

    testWidgets('a steal: open field, drag, chip, commit', (tester) async {
      await runnerOnFirstThenField(tester);
      expect(find.byKey(fieldIdleLabelKey), findsOneWidget);
      // No batted ball, so no trajectory — but the same ✓ a play commits
      // with, because a between-pitch entry accumulates a chain too.
      expect(find.byKey(trajectoryEditKey), findsNothing);
      expect(find.byKey(fieldCommitKey), findsOneWidget);

      await dragToken(tester, 1, 2, target: 'base');
      await tapKey(tester, safeChipKey('stolen_base'));
      await tapKey(tester, fieldCommitKey);

      final advances = (await stream())
          .where((e) => e.type == 'RunnerAdvance')
          .map((e) => RunnerAdvance.fromJson(e.payload))
          .toList();
      final steal = advances.last;
      expect(steal.runnerId, 'opp-1');
      expect((steal.from, steal.to), (1, 2));
      expect(steal.reason, RunnerAdvanceReason.STOLEN_BASE);
      expect(
        container.read(gameControllerProvider).value!.bases.second,
        'opp-1',
      );
    });

    testWidgets('a pickoff: the throw over, and she does not get back', (
      tester,
    ) async {
      // "Picked off" has been on the OUT menu since DIA-008d and had **zero**
      // test coverage — untested rather than unbuilt, which is the worse of
      // the two to not know about.
      //
      // Consequence-free attempts are deliberately out of scope (Mark,
      // 2026-08-27): a throw over that the runner dives back into safely
      // records nothing, which is why `PickoffAttempt` was never needed.
      await runnerOnFirstThenField(tester);
      await tapWorld(
        tester,
        standardFielderSpots(FieldProfile.fastpitch12U)[3]!,
      );
      await dragToken(tester, 1, 1, target: 'out', originFrom: 1);
      await tapKey(tester, outChipKey('picked_off'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final out = events
          .where((e) => e.type == 'RunnerOut')
          .map((e) => RunnerOut.fromJson(e.payload))
          .single;
      expect(out.how, How.PICKED_OFF);
      expect(out.runnerId, 'opp-1');
      expect(container.read(gameControllerProvider).value!.outs, 1);
      expect(
        container.read(gameControllerProvider).value!.bases.first,
        isNull,
        reason: 'she is off the base she was picked off',
      );
    });

    testWidgets('caught stealing carries the throw: 2-6 putout and assist', (
      tester,
    ) async {
      await runnerOnFirstThenField(tester);
      // The catcher has the ball, so tapping the shortstop throws to her.
      await tapWorld(
        tester,
        standardFielderSpots(FieldProfile.fastpitch12U)[6]!,
      );
      await dragToken(tester, 1, 2, target: 'out');
      await tapKey(tester, outChipKey('caught_stealing'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events
          .where((e) => e.type == 'FielderTouch')
          .map((e) => FielderTouch.fromJson(e.payload))
          .toList();
      expect(touches.map((t) => t.position), [2, 6]);
      expect(touches.first.touchType, TouchType.FIELDED);
      expect(touches.last.touchType, TouchType.RECEIVED_THROW);

      final scoring = foldOfficialScoring(events);
      expect(scoring.putoutsByPosition, {6: 1});
      expect(scoring.assistsByPosition, {2: 1});
      expect(container.read(gameControllerProvider).value!.outs, 1);
    });

    testWidgets('a fielder drags to where she made the play, and the touch '
        'records it (§4.2)', (tester) async {
      await runnerOnFirstThenField(tester);
      final geometry = canvasGeometry(tester);
      // The shortstop covers second — she is not at her standard spot.
      final bag = geometry.baseCoord(2);
      await drag(
        tester,
        canvasTopLeft(tester) +
            geometry.toPx(standardFielderSpots(geometry.profile)[6]!),
        canvasTopLeft(tester) + geometry.toPx(bag),
      );
      await dragToken(tester, 1, 2, target: 'out');
      await tapKey(tester, outChipKey('caught_stealing'));
      await tapKey(tester, fieldCommitKey);

      final touch = FielderTouch.fromJson(
        (await stream()).lastWhere((e) => e.type == 'FielderTouch').payload,
      );
      expect(touch.position, 6);
      expect(touch.location, isNotNull);
      // Where she took it, not where she starts the inning.
      expect(touch.location!.x, closeTo(bag.x, 6));
      expect(touch.location!.y, closeTo(bag.y, 6));
    });

    testWidgets('a passed ball emits the §13.2 pair, linked', (tester) async {
      await runnerOnFirstThenField(tester);
      await dragToken(tester, 1, 2, target: 'base');
      await tapKey(tester, safeChipKey('passed_ball'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touch = events.lastWhere((e) => e.type == 'FielderTouch');
      final payload = FielderTouch.fromJson(touch.payload);
      expect(payload.position, 2);
      expect(payload.touchType, TouchType.MISSED_CATCH);
      // Anchored to the pitch, not a BallInPlay — there is no batted ball.
      final lastPitch = events.lastWhere((e) => e.type == 'PitchThrown');
      expect(payload.anchorEventId, lastPitch.id);

      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.PASSED_BALL);
      expect(advance.enabledByTouchId, touch.id);

      final scoring = foldOfficialScoring(events);
      expect(scoring.passedBalls, 1);
      expect(scoring.errors, isEmpty, reason: 'a PB is never an error');
    });

    testWidgets('the catcher never had it: 1B off the backstop, throw home '
        'records 3-2 with no phantom assist', (tester) async {
      await runnerOnFirstThenField(tester);
      final geometry = canvasGeometry(tester);
      Offset px(FieldCoord c) => canvasTopLeft(tester) + geometry.toPx(c);
      final spots = standardFielderSpots(geometry.profile);

      // The line says who has it, and how to say she doesn't.
      expect(
        tester.widget<Text>(find.byKey(fieldIdleLabelKey)).data,
        contains('Catcher has the ball'),
      );
      // Tap the catcher: she never had it, the ball got past her.
      await tester.tapAt(px(spots[2]!));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(fieldIdleLabelKey)).data,
        contains('loose'),
      );

      // The first baseman runs it down behind the plate, then throws home.
      final backstop = FieldCoord(x: 20, y: -14);
      await drag(tester, px(spots[3]!), px(backstop));
      // A loose ball asks what happened, in either state of the screen.
      await tapKey(tester, fielderPlayKey('picked_up'));
      await tester.tapAt(px(spots[2]!));
      await tester.pumpAndSettle();

      await dragToken(tester, 1, 2, target: 'out');
      await tapKey(tester, outChipKey('caught_stealing'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final touches = events
          .where((e) => e.type == 'FielderTouch')
          .map((e) => FielderTouch.fromJson(e.payload))
          .toList();
      // 3-2, not 2-3-2: the catcher is credited only for what she did.
      expect(touches.map((t) => t.position), [3, 2]);
      expect(touches.first.touchType, TouchType.FIELDED);
      expect(touches.last.touchType, TouchType.RECEIVED_THROW);
      expect(touches.first.location!.y, lessThan(0), reason: 'behind home');

      final scoring = foldOfficialScoring(events);
      expect(scoring.putoutsByPosition, {2: 1});
      expect(scoring.assistsByPosition, {3: 1});
    });

    testWidgets('CS at third, but a missed tag: she is safe and the error '
        'is charged — the chain is why this is enterable', (tester) async {
      await runnerOnFirstThenField(tester);
      final geometry = canvasGeometry(tester);
      // Catcher throws to third; the third baseman muffs the tag.
      await tester.tapAt(
        canvasTopLeft(tester) +
            geometry.toPx(standardFielderSpots(geometry.profile)[5]!),
      );
      await tester.pumpAndSettle();
      // Retype her touch to a missed tag — the chain strip's chip, the same
      // one a play uses.
      await tapKey(tester, chainNodeKey(1));
      await tapKey(tester, chainChipKey('tag_missed'));

      await dragToken(tester, 1, 3);
      await tapKey(tester, safeChipKey('error'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      final scoring = foldOfficialScoring(events);
      // A muffed tag is a fielding error (§13.2 v0.43) once it has a
      // consequence, and the consequence is that she is standing on third.
      expect(scoring.errors.single.position, 5);
      expect(
        container.read(gameControllerProvider).value!.bases.third,
        'opp-1',
      );
      expect(container.read(gameControllerProvider).value!.outs, 0);
    });

    testWidgets('a wild pitch is the advance alone — no touch is minted', (
      tester,
    ) async {
      await runnerOnFirstThenField(tester);
      final touchesBefore = (await stream())
          .where((e) => e.type == 'FielderTouch')
          .length;

      await dragToken(tester, 1, 2, target: 'base');
      await tapKey(tester, safeChipKey('wild_pitch'));
      await tapKey(tester, fieldCommitKey);

      final events = await stream();
      // §13.2: a wild pitch is an uncaught pitch with NO catcher touch —
      // the absence is what makes it one, so minting a touch here would
      // silently convert it into a passed ball.
      expect(
        events.where((e) => e.type == 'FielderTouch'),
        hasLength(touchesBefore),
      );
      final advance = RunnerAdvance.fromJson(
        events.lastWhere((e) => e.type == 'RunnerAdvance').payload,
      );
      expect(advance.reason, RunnerAdvanceReason.WILD_PITCH);
      expect(advance.enabledByTouchId, isNull);

      final scoring = foldOfficialScoring(events);
      expect(scoring.passedBalls, 0);
      expect(scoring.wildPitchesByPitcher, {'own-p1': 1});
    });

    testWidgets('one undo reverses the steal and never the pitch before it', (
      tester,
    ) async {
      await runnerOnFirstThenField(tester);
      final before = (await stream()).length;

      await dragToken(tester, 1, 2, target: 'base');
      await tapKey(tester, safeChipKey('stolen_base'));
      await tapKey(tester, fieldCommitKey);
      expect((await stream()).length, before + 1);

      await container.read(gameControllerProvider.notifier).undoLast();
      await tester.pumpAndSettle();

      final after = await stream();
      expect(after.length, before, reason: 'exactly the steal came off');
      // The walk that put her on first is untouched: still on first, and
      // the four pitches still stand.
      expect(
        container.read(gameControllerProvider).value!.bases.first,
        'opp-1',
      );
      expect(after.where((e) => e.type == 'PitchThrown'), hasLength(4));
    });
  });

  group('play #5 through the UI (DIA-008 accept)', () {
    testWidgets('D3K, wild throw to first: batter to 2nd, R1 to 3rd, a '
        'strikeout with no out', (tester) async {
      await pumpLoop(tester);

      Future<void> pitch(String outcome) async {
        await tester.tap(find.text('Skip call'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Skip location'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(outcome));
        await tester.pumpAndSettle();
      }

      // Two away, then a runner on first — play #5's setup.
      for (var k = 0; k < 2; k++) {
        for (var i = 0; i < 3; i++) {
          await pitch('Called strike');
        }
      }
      for (var i = 0; i < 4; i++) {
        await pitch('Ball');
      }
      expect(container.read(gameControllerProvider).value!.outs, 2);

      // Strike three she is entitled to run on: two are out. It is declared
      // on the outcome sheet, beside In play — the automatic strikeout is
      // never written, so there is nothing to void.
      for (var i = 0; i < 2; i++) {
        await pitch('Called strike');
      }
      await tester.tap(find.text('Skip call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip location'));
      await tester.pumpAndSettle();
      await tapKey(tester, outcomeD3kKey);
      await tapKey(tester, d3kSwingingKey);
      await tapKey(tester, d3kFieldKey);

      // The field opens with her already running to first, catcher holding.
      final geometry = canvasGeometry(tester);
      expect(find.byKey(fieldIdleLabelKey), findsOneWidget);

      // Catcher throws to first, and airmails it.
      await tester.tapAt(
        canvasTopLeft(tester) +
            geometry.toPx(standardFielderSpots(geometry.profile)[3]!),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, chainNodeKey(2));
      await tapKey(tester, chainChipKey('wild_throw'));
      // v0.56: nothing further is needed to make this chargeable. The throw
      // charges because a runner advanced on it, full stop — until v0.56 it
      // defaulted to "unresolved" and charged nobody unless the scorer found
      // a switch, which meant real throwing errors went unrecorded.

      // The throw arriving at first with her running raises the force
      // question at the bag: she beat it, because it sailed.
      await tapPill(tester, 1);

      // Both runners then take the extra base on the same throw. The lead
      // runner first — runners never pass one another, so moving the
      // trailing one first would push her along too (§15.1's cascade).
      await dragToken(tester, 2, 3, originFrom: 1);
      await tapKey(tester, safeChipKey('error'));
      await dragToken(tester, 1, 2);
      await tapKey(tester, safeChipKey('error'));
      await tapKey(tester, fieldCommitKey);

      final state = container.read(gameControllerProvider).value!;
      expect(state.outs, 2, reason: 'a strikeout with no out recorded');
      expect(state.bases.second, isNotNull);
      expect(state.bases.third, isNotNull);

      final scoring = foldOfficialScoring(await stream());
      expect(scoring.errors.single.position, 2);
      expect(scoring.errors.single.kind, OfficialErrorKind.throwing);
      expect(scoring.strikeoutsByPitcher.values.single, 3);
    });
  });
}
