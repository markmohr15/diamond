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
}

final playJournalStoreProvider = Provider<PlayJournalStore>(
  (ref) => PlayJournalStore(ref.watch(appDatabaseProvider)),
);
