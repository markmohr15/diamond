import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_journal_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PlayJournalStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = PlayJournalStore(db);
  });
  tearDown(() => db.close());

  group('PlayJournalStore (§15.5 crash journal)', () {
    test('empty journal loads null', () async {
      expect(await store.load('m1-game'), isNull);
    });

    test('saves and restores a draft, fields intact', () async {
      final draft = const PlayDraft(pitchEventId: 'p-1', batterId: 'opp-1')
          .copyWith(
            landing: FieldCoord(x: -45, y: 120),
            trajectory: Trajectory.LINE,
          )
          .addingLeg('opp-1', from: 0, to: 1);
      await store.save('m1-game', draft);

      final restored = await store.load('m1-game');
      expect(restored!.pitchEventId, 'p-1');
      expect(restored.landing!.x, -45);
      expect(restored.trajectory, Trajectory.LINE);
      expect((restored.entries.single as LegEntry).to, 1);
    });

    test('one row per game: each save replaces the last', () async {
      const draft = PlayDraft(pitchEventId: 'p-1', batterId: 'opp-1');
      await store.save('m1-game', draft);
      await store.save(
        'm1-game',
        draft.copyWith(trajectory: Trajectory.GROUND),
      );
      final restored = await store.load('m1-game');
      expect(restored!.trajectory, Trajectory.GROUND);
    });

    test('clear removes the row; games do not share journals', () async {
      const draft = PlayDraft(pitchEventId: 'p-1', batterId: 'opp-1');
      await store.save('m1-game', draft);
      await store.save('other-game', draft);
      await store.clear('m1-game');
      expect(await store.load('m1-game'), isNull);
      expect(await store.load('other-game'), isNotNull);
    });
  });

  group('committed plays (§15.5 v0.63: undo reopens them)', () {
    const steal = PlayDraft(
      pitchEventId: 'p-1',
      batterId: '',
      battedBall: false,
    );
    const play = PlayDraft(pitchEventId: 'p-2', batterId: 'opp-1');

    test('takes the newest match and removes it', () async {
      await store.pushCommitted('g', steal);
      await store.pushCommitted('g', play);

      final taken = await store.takeCommitted(
        'g',
        (d) => d.battedBall && d.pitchEventId == 'p-2',
      );
      expect(taken?.pitchEventId, 'p-2');
      expect(
        await store.takeCommitted('g', (d) => d.pitchEventId == 'p-2'),
        isNull,
        reason: 'taken once',
      );
      expect(
        (await store.takeCommitted('g', (d) => !d.battedBall))?.pitchEventId,
        'p-1',
      );
    });

    test('lives beside the crash journal without touching it', () async {
      await store.save('g', play);
      await store.pushCommitted('g', steal);
      expect((await store.load('g'))?.pitchEventId, 'p-2');
      await store.clear('g');
      expect(
        await store.takeCommitted('g', (_) => true),
        isNotNull,
        reason: 'clearing the open draft keeps the committed copies',
      );
    });

    test('keeps only the last ${PlayJournalStore.committedDepth}', () async {
      for (var i = 0; i < PlayJournalStore.committedDepth + 3; i++) {
        await store.pushCommitted(
          'g',
          PlayDraft(pitchEventId: 'p-$i', batterId: 'b'),
        );
      }
      expect(
        await store.takeCommitted('g', (d) => d.pitchEventId == 'p-0'),
        isNull,
      );
      expect(
        await store.takeCommitted('g', (d) => d.pitchEventId == 'p-12'),
        isNotNull,
      );
    });
  });
}
