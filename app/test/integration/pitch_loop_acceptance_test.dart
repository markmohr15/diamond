import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/field_canvas/field_entry_surface.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:diamond/src/ui/loop/count_hud.dart';
import 'package:diamond/src/ui/loop/pitch_loop_page.dart';
import 'package:diamond/src/ui/theme/derive_scheme.dart';
import 'package:diamond/src/ui/theme/team_colors.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// DIA-007's acceptance: the scripted at-bat, driven entirely through the UI,
/// asserted against the exact event stream and the HUD states along the way.
///
/// The script: a 6-pitch AB — ball, called strike, **unknown** (amber),
/// CountCorrection to 2-1 (amber clears), foul, ball, ball four — walk with
/// the forced advance confirmed (§11.3); then an in-play pitch located
/// *after* the play via "record last pitch," asserting the §6 correction
/// chain on `PitchThrown` (§11.1 v0.39).
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) {
          final db = AppDatabase(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pumpLoop(WidgetTester tester) async {
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
          home: const PitchLoopPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// The most recent visible pitch — post-undo, the §6 chains have already
  /// collapsed or vanished.
  Future<PitchThrown> lastPitch() async {
    final session = container.read(gameSessionProvider);
    final events = await container
        .read(eventStoreProvider)
        .readStream(session.gameId);
    return PitchThrown.fromJson(
      events.lastWhere((e) => e.type == 'PitchThrown').payload,
    );
  }

  Future<void> tapCanvasAt(WidgetTester tester, ZoneCoord coord) async {
    final area = find.byKey(zoneCanvasDrawingAreaKey);
    final topLeft = tester.getTopLeft(area);
    await tester.tapAt(
      topLeft + localFromZoneCoord(coord, tester.getSize(area)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> placeActualAt(WidgetTester tester, ZoneCoord coord) async {
    final area = find.byKey(zoneCanvasDrawingAreaKey);
    final topLeft = tester.getTopLeft(area);
    final gesture = await tester.startGesture(
      topLeft + localFromZoneCoord(coord, tester.getSize(area)),
    );
    await tester.pump(zoneCanvasArmDuration + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// One skipped-entry pitch: skip call, skip location, tap [outcome].
  Future<void> quickPitch(WidgetTester tester, String outcome) async {
    await tapText(tester, 'Skip call');
    await tapText(tester, 'Skip location');
    await tapText(tester, outcome);
  }

  testWidgets('the scripted AB: 6 pitches with an unknown + correction, '
      'a confirmed walk, and a post-play located in-play pitch', (
    tester,
  ) async {
    await pumpLoop(tester);
    final session = container.read(gameSessionProvider);

    // P1 — called and thrown: fastball middle, taken outside for a ball.
    await tapText(tester, 'Fastball');
    await tapCanvasAt(tester, ZoneCoord(x: 0, y: 0.5)); // c2r2
    await tester.tap(find.byKey(callScreenPitchThrownKey));
    await tester.pumpAndSettle();
    await placeActualAt(tester, ZoneCoord(x: 1.6, y: 0.5));
    await tapText(tester, 'Ball'); // the suggestion, tapped from the big button
    expect(find.text('1-0', findRichText: true), findsOneWidget);

    // P2 — called strike.
    await quickPitch(tester, 'Called strike');
    expect(find.text('1-1', findRichText: true), findsOneWidget);

    // P3 — the scorer looked up and the count changed (§12.5).
    await quickPitch(tester, 'Unknown');
    final amberHud = tester.widget<Container>(find.byKey(countHudKey));
    expect(
      amberHud.color,
      isNot(
        Theme.of(
          tester.element(find.byKey(countHudKey)),
        ).colorScheme.surfaceContainerHigh,
      ),
    );
    // unchanged — never guessed
    expect(find.text('1-1', findRichText: true), findsOneWidget);

    // The checkpoint: scoreboard says 2-1, make it so.
    await tester.longPress(find.byKey(countHudCountKey));
    await tester.pumpAndSettle();
    // Both chip rows show a '2'; the balls row renders first.
    await tester.tap(find.widgetWithText(ChoiceChip, '2').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Make it 2-1');
    expect(find.text('2-1', findRichText: true), findsOneWidget);
    final clearedHud = tester.widget<Container>(find.byKey(countHudKey));
    expect(
      clearedHud.color,
      Theme.of(
        tester.element(find.byKey(countHudKey)),
      ).colorScheme.surfaceContainerHigh,
      reason: 'the checkpoint clears the amber (§12.5)',
    );

    // P4–P6: foul, ball, ball four.
    await quickPitch(tester, 'Foul');
    expect(find.text('2-2', findRichText: true), findsOneWidget);
    await quickPitch(tester, 'Ball');
    expect(find.text('3-2', findRichText: true), findsOneWidget);
    await quickPitch(tester, 'Ball');

    // Ball four: the forced advance auto-applied (§11.3 v0.41) — no
    // confirmation, straight back to the call screen with the runner placed.
    expect(find.byType(CallScreen), findsOneWidget);
    var gs = container.read(gameControllerProvider).requireValue;
    expect(gs.bases.first, 'opp-1');
    expect(gs.batterDue('opp'), 'opp-2');
    expect(find.text('0-0', findRichText: true), findsOneWidget);

    // P7 — opp-2 puts it in play; nobody saw where it crossed. The field
    // surface opens (§15.1, DIA-008a); this script discards the play — its
    // subject is the pitch loop, and DIA-009's scripted half-inning is where
    // plays get scored for real.
    await quickPitch(tester, 'In play');
    // Score the ball and commit it. ✕ used to be the quick way off this
    // surface, but cancel now restarts the play rather than abandoning it
    // (v0.54) — an `in_play` pitch can no longer be left with no play.
    await tester.tap(find.byKey(trajectoryKey(Trajectory.GROUND)));
    await tester.pumpAndSettle();
    final canvas = find.byKey(fieldCanvasKey);
    await tester.tapAt(
      tester.getTopLeft(canvas) +
          FieldGeometry(
            profile: FieldProfile.fastpitch12U,
            size: tester.getSize(canvas),
          ).toPx(FieldCoord(x: 0, y: 120)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(fieldCommitKey));
    await tester.pumpAndSettle();

    // The loop returns offering to fix that (§11.1 v0.39) — blocking nothing.
    expect(find.byKey(recordLastPitchKey), findsOneWidget);
    expect(find.byType(CallScreen), findsOneWidget);
    await tester.tap(find.byKey(recordLastPitchKey));
    await tester.pumpAndSettle();
    await placeActualAt(tester, ZoneCoord(x: 0.5, y: 0.4));
    expect(find.byKey(recordLastPitchKey), findsNothing);

    // ——— The exact stream (§14-style assertion). ———
    final store = container.read(eventStoreProvider);
    final visible = await store.readStream(session.gameId);

    expect(visible.map((e) => e.type).toList(), [
      'LineupSet',
      'InningHalfStart',
      'PitchThrown', // P1 ball
      'PitchThrown', // P2 called strike
      'PitchThrown', // P3 unknown
      'CountCorrection',
      'PitchThrown', // P4 foul
      'PitchThrown', // P5 ball
      'PitchThrown', // P6 ball four
      'RunnerAdvance', // the confirmed walk
      'PitchThrown', // P7 in play — corrected version, original position
      // The ball in play is now *scored* rather than discarded (v0.54):
      // cancel restarts a play instead of abandoning it, so committing is
      // the only exit that keeps the pitch. A truer script for it — a real
      // scorer never leaves an `in_play` pitch with no play recorded.
      'BallInPlay',
      'RunnerAdvance', // the batter's walk-up to first
      'RunnerAdvance', // and her advance on the grounder
    ]);

    final pitches = visible
        .where((e) => e.type == 'PitchThrown')
        .map((e) => PitchThrown.fromJson(e.payload))
        .toList();
    expect(pitches.map((p) => p.outcome).toList(), [
      Outcome.BALL,
      Outcome.CALLED_STRIKE,
      Outcome.UNKNOWN,
      Outcome.FOUL,
      Outcome.BALL,
      Outcome.BALL,
      Outcome.IN_PLAY,
    ]);

    // P1 carried the full intent and the observed actual.
    expect(pitches.first.intendedZoneId, 'c2r2');
    expect(pitches.first.actualLocation!.x, closeTo(1.6, 0.05));

    final correction = CountCorrection.fromJson(visible[5].payload);
    expect((correction.balls, correction.strikes), (2, 1));

    final walk = RunnerAdvance.fromJson(visible[9].payload);
    expect(walk.runnerId, 'opp-1');
    expect((walk.from, walk.to), (0, 1));
    expect(walk.reason, RunnerAdvanceReason.WALK);

    // P7's visible version carries the backfilled location (§6: the chain
    // collapses to the latest version at the original's position)…
    final inPlay = pitches.last;
    expect(inPlay.batterId, 'opp-2');
    expect(inPlay.actualLocation!.x, closeTo(0.5, 0.05));
    expect(inPlay.actualLocation!.y, closeTo(0.4, 0.05));

    // …and the raw stream shows how it got there: a correction pointing at
    // the original unlocated pitch.
    //
    // Found by *following the link* rather than by position. These used to
    // index off the end of the raw stream and off `visible.last`, which held
    // only while the play was discarded; committing it put three events
    // after the pitch and both assertions broke. A correction is also shown
    // at its original's position, so it is never last in the visible order
    // anyway — the old assertion passed by coincidence.
    final raw = await store.readRawStream(session.gameId);
    final corrected = raw.lastWhere((e) => e.corrects != null);
    final original = raw.firstWhere((e) => e.id == corrected.corrects);
    expect(PitchThrown.fromJson(original.payload).actualLocation, isNull);
    expect(
      visible.map((e) => e.id),
      contains(corrected.id),
      reason: 'the corrected version is what projections see',
    );
    expect(
      visible.map((e) => e.id),
      isNot(contains(original.id)),
      reason: 'and the superseded one is not',
    );

    // Final state: the walk on, and the ball in play *scored* on top of it
    // (v0.54 — cancel restarts a play, so committing is the only exit that
    // keeps the pitch). opp-2 reached on the grounder and forced opp-1 to
    // second; the script used to discard that play, so first stayed opp-1.
    gs = container.read(gameControllerProvider).requireValue;
    expect(gs.bases.first, 'opp-2');
    expect(gs.bases.second, 'opp-1');
    expect(gs.batterDue('opp'), 'opp-3');
    expect((gs.balls, gs.strikes), (0, 0));
    expect(gs.pitchCountByPitcher[session.pitcherId], 7);

    // ——— Action-scoped undo, bounded at the plate appearance ———
    // (§6, §11.3 v0.41, and v0.54's seal.) This script used to peel three
    // levels straight through a plate-appearance boundary and assert the
    // walk came back. It cannot any more, and that is the point of the
    // seal: undo takes back what the scorer just did, and DIA-020's
    // editing surface — not this button — reaches into a finished batter.

    // Undo #1: the committed play, as one unit. It goes first because a
    // correction is shown at its *original's* position, so the play's
    // events are the last visible ones.
    await tester.tap(find.byKey(countHudUndoKey));
    await tester.pumpAndSettle();
    gs = container.read(gameControllerProvider).requireValue;
    expect(gs.bases.first, 'opp-1', reason: 'back to just the walk');
    expect(gs.bases.second, isNull);

    // Undo #2: the §6 correction — the backfilled location goes, the pitch
    // stays. A correction unwind, so nothing is voided and nothing seals.
    await tester.tap(find.byKey(countHudUndoKey));
    await tester.pumpAndSettle();
    expect((await lastPitch()).actualLocation, isNull);
    expect((await lastPitch()).outcome, Outcome.IN_PLAY);

    // Undo #3: the in-play pitch itself; opp-2's PA reopens. Still hers, so
    // still reachable.
    await tester.tap(find.byKey(countHudUndoKey));
    await tester.pumpAndSettle();
    gs = container.read(gameControllerProvider).requireValue;
    expect(gs.batterDue('opp'), 'opp-2');

    // Undo #4 is refused: the next tap would cross into opp-1, whose walk
    // is a finished plate appearance. The button says so rather than
    // silently declining.
    expect(
      tester.widget<IconButton>(find.byKey(countHudUndoKey)).onPressed,
      isNull,
      reason: 'sealed, and the button shows it',
    );
    await tester.tap(find.byKey(countHudUndoKey), warnIfMissed: false);
    await tester.pumpAndSettle();
    gs = container.read(gameControllerProvider).requireValue;
    expect(gs.bases.first, 'opp-1', reason: 'the walk stands');
  });
}
