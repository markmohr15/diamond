import 'package:diamond/src/events/generated/events.dart';

const _voidEventType = 'VoidEvent';

/// Resolves a raw chronological event list (every event, including voided
/// and superseded ones) into the visible, logically-ordered stream a
/// projection should fold over (spec §5, §6, §7).
///
/// Two independent passes:
/// 1. [spliceEffectiveAfter] repositions backdated inserts — "we missed the
///    stolen base two pitches ago" — without touching visibility.
/// 2. [applyVisibility] hides voided events and collapses correction chains
///    to their latest version, at the position from step 1.
///
/// Splicing before filtering means an insert anchored to an event that was
/// later voided or superseded still lands at a stable position: anchor
/// resolution always uses the anchor's *raw* chronological slot, never
/// whether it ended up visible.
List<GameEvent> resolveVisibleLogicalOrder(List<GameEvent> chronological) {
  return applyVisibility(spliceEffectiveAfter(chronological));
}

/// Repositions every `effectiveAfter`-tagged event to sit immediately after
/// its anchor (resolved through the anchor's correction chain to its root),
/// using the anchor's position in [chronological] — not the anchor's
/// visibility. Anchors resolve transitively: an insert anchored to another
/// insert ends up immediately after that insert, wherever it lands.
///
/// Multiple events anchored to the same target tie-break by their own
/// recording order (their position in [chronological]).
List<GameEvent> spliceEffectiveAfter(List<GameEvent> chronological) {
  final byId = {for (final e in chronological) e.id: e};

  String? correctionRootOf(String id) {
    var current = id;
    var next = byId[current]?.corrects;
    while (next != null && byId.containsKey(next)) {
      current = next;
      next = byId[current]?.corrects;
    }
    return byId.containsKey(current) ? current : null;
  }

  // childId -> resolved anchor (parent) id, only for valid, non-self anchors.
  final anchorParentOf = <String, String>{};
  for (final e in chronological) {
    final ref = e.effectiveAfter;
    if (ref == null) continue;
    final root = correctionRootOf(ref);
    if (root != null && root != e.id) {
      anchorParentOf[e.id] = root;
    }
  }

  // Children grouped by parent, already in recording order since
  // `chronological` is iterated in order.
  final childrenOf = <String, List<GameEvent>>{};
  for (final e in chronological) {
    final parent = anchorParentOf[e.id];
    if (parent != null) {
      (childrenOf[parent] ??= []).add(e);
    }
  }

  final result = <GameEvent>[];
  final emitted = <String>{};

  void emit(GameEvent e) {
    if (!emitted.add(e.id)) return; // defensive: cycle/dup guard
    result.add(e);
    for (final child in childrenOf[e.id] ?? const <GameEvent>[]) {
      emit(child);
    }
  }

  for (final e in chronological) {
    if (anchorParentOf.containsKey(e.id)) continue; // emitted via its parent
    emit(e);
  }

  return result;
}

/// Hides voided events and collapses correction chains to their latest
/// version, surfaced at the position of the chain's root in [ordered].
/// Generic over whatever order it's given — chronological or spliced.
List<GameEvent> applyVisibility(List<GameEvent> ordered) {
  final byId = {for (final e in ordered) e.id: e};

  // Recording order within `ordered` means the last write for a given
  // target is the active correction — matches "projections use the latest
  // version".
  final latestChildOf = <String, GameEvent>{};
  for (final e in ordered) {
    final target = e.corrects;
    if (target != null) {
      latestChildOf[target] = e;
    }
  }

  String headOf(String id) {
    var current = id;
    while (latestChildOf.containsKey(current)) {
      current = latestChildOf[current]!.id;
    }
    return current;
  }

  String rootOf(String id) {
    var current = id;
    var next = byId[current]?.corrects;
    while (next != null && byId.containsKey(next)) {
      current = next;
      next = byId[current]?.corrects;
    }
    return current;
  }

  final voidedRoots = <String>{};
  for (final e in ordered) {
    if (e.type == _voidEventType) {
      final target = VoidEvent.fromJson(e.payload).targetId;
      if (byId.containsKey(target)) {
        voidedRoots.add(rootOf(target));
      }
    }
  }

  final resolved = <GameEvent>[];
  for (final e in ordered) {
    if (e.type == _voidEventType) continue;
    if (e.corrects != null) continue; // only shown via its chain's root
    if (voidedRoots.contains(e.id)) continue;
    resolved.add(byId[headOf(e.id)]!);
  }
  return resolved;
}
