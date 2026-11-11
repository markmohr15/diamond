import 'dart:convert';

import 'package:diamond/src/events/database/app_database.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persistence for the one uncommitted play (§15.5): save on every draft
/// mutation, load on relaunch, clear on commit or discard. See the
/// `PlayJournals` table for why this lives beside — never inside — the
/// event stream.
class PlayJournalStore {
  PlayJournalStore(this._db);

  final AppDatabase _db;

  Future<void> save(String gameId, PlayDraft draft) {
    return _db
        .into(_db.playJournals)
        .insertOnConflictUpdate(
          PlayJournalsCompanion.insert(
            gameId: gameId,
            draft: jsonEncode(draft.toJson()),
          ),
        );
  }

  Future<PlayDraft?> load(String gameId) async {
    final query = _db.select(_db.playJournals)
      ..where((tbl) => tbl.gameId.equals(gameId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return PlayDraft.fromJson(jsonDecode(row.draft) as Map<String, dynamic>);
  }

  Future<void> clear(String gameId) {
    return (_db.delete(
      _db.playJournals,
    )..where((tbl) => tbl.gameId.equals(gameId))).go();
  }

  /// The plays as the scorer entered them, newest first, so undoing one can
  /// put it back on the field to edit (§15.5 v0.63) the way undoing a pitch
  /// hands back its call and location.
  ///
  /// An editing aid, not the record: the events are the record, and nothing
  /// here is ever read to derive anything. It shares the journal's table
  /// under a second key per game rather than taking a table of its own,
  /// because it is the same kind of thing — a draft kept beside the stream —
  /// and a migration for it would buy nothing.
  static String _committedKey(String gameId) => '$gameId#committed';

  /// How many committed plays are kept. Undo stops at the plate appearance
  /// (§11.3 v0.54), so only the last few can ever be asked for.
  static const committedDepth = 10;

  Future<void> pushCommitted(String gameId, PlayDraft draft) async {
    final kept = await _committed(gameId);
    final next = [draft, ...kept].take(committedDepth).toList();
    await _db
        .into(_db.playJournals)
        .insertOnConflictUpdate(
          PlayJournalsCompanion.insert(
            gameId: _committedKey(gameId),
            draft: jsonEncode([for (final d in next) d.toJson()]),
          ),
        );
  }

  /// Removes and returns the newest committed play that [matches], or null
  /// when none was kept — a play committed before this existed, or on a
  /// store that was cleared.
  Future<PlayDraft?> takeCommitted(
    String gameId,
    bool Function(PlayDraft) matches,
  ) async {
    final kept = await _committed(gameId);
    final index = kept.indexWhere(matches);
    if (index < 0) return null;
    final taken = kept.removeAt(index);
    await _db
        .into(_db.playJournals)
        .insertOnConflictUpdate(
          PlayJournalsCompanion.insert(
            gameId: _committedKey(gameId),
            draft: jsonEncode([for (final d in kept) d.toJson()]),
          ),
        );
    return taken;
  }

  Future<List<PlayDraft>> _committed(String gameId) async {
    final query = _db.select(_db.playJournals)
      ..where((tbl) => tbl.gameId.equals(_committedKey(gameId)));
    final row = await query.getSingleOrNull();
    if (row == null) return [];
    return [
      for (final json in jsonDecode(row.draft) as List<dynamic>)
        PlayDraft.fromJson(json as Map<String, dynamic>),
    ];
  }
}

final playJournalStoreProvider = Provider<PlayJournalStore>(
  (ref) => PlayJournalStore(ref.watch(appDatabaseProvider)),
);
