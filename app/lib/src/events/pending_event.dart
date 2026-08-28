import 'package:flutter/foundation.dart';

/// One event awaiting append: type + payload, envelope-less. The write path
/// (`GameController`) owns ids and sequence numbers at append time, so
/// nothing upstream — a play draft, a fixture loader — can invent them.
///
/// **Intra-batch references:** events committed together may need each
/// other's ids before those ids exist (`FielderTouch.anchorEventId`,
/// `RunnerAdvance.enabledByTouchId`, `RunnerOut.putoutTouchId`, §4.2–4.3).
/// An event that others reference declares a [localKey]; a payload value of
/// the form `{"$local": <key>}` (see [localRef]) is replaced with that
/// event's real id during append, after envelopes are built. Keys are
/// batch-scoped and never leave the write path.
@immutable
class PendingEvent {
  const PendingEvent({
    required this.type,
    required this.payload,
    this.localKey,
  });

  final String type;
  final Map<String, dynamic> payload;

  /// Batch-scoped name other events in the same batch may reference via
  /// [localRef]. Null for events nothing points at.
  final String? localKey;
}

/// A payload value standing in for the id of the batch-mate whose
/// [PendingEvent.localKey] is [key].
Map<String, dynamic> localRef(String key) => {r'$local': key};

/// Deep-replaces every [localRef] value in [payload] with the real id from
/// [idsByKey]. Throws [StateError] on a dangling key — a draft bug, not an
/// input.
Map<String, dynamic> resolveLocalRefs(
  Map<String, dynamic> payload,
  Map<String, String> idsByKey,
) {
  Object? resolve(Object? value) {
    if (value is Map) {
      final local = value[r'$local'];
      if (local != null && value.length == 1) {
        final id = idsByKey[local];
        if (id == null) {
          throw StateError('dangling local ref: $local');
        }
        return id;
      }
      return {
        for (final entry in value.entries)
          entry.key as String: resolve(entry.value),
      };
    }
    if (value is List) return [for (final item in value) resolve(item)];
    return value;
  }

  return resolve(payload)! as Map<String, dynamic>;
}
