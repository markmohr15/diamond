import 'dart:math';

import 'package:diamond/src/call/team_config.dart';
import 'package:flutter/foundation.dart';

/// A call: one pitch type at one call zone. Zone identity is batter-relative
/// (§10.1), so the same call means the same thing to every batter — which is
/// the whole reason a code can be printed at all.
@immutable
class Call {
  const Call({required this.pitchTypeId, required this.zoneId});

  final String pitchTypeId;
  final String zoneId;

  @override
  bool operator ==(Object other) =>
      other is Call &&
      other.pitchTypeId == pitchTypeId &&
      other.zoneId == zoneId;

  @override
  int get hashCode => Object.hash(pitchTypeId, zoneId);

  @override
  String toString() => '$pitchTypeId@$zoneId';
}

/// One cell on the printed card (§10.2).
///
/// The spoken form *is* the grid coordinate — first digit the row, the rest the
/// column label — because lookup has to be O(1): a ten-year-old finds row 5,
/// column 39 in two seconds, where scanning a flat list of random numbers
/// between pitches is misery. The security lives in the contents, not the
/// coordinates: assignments are randomized per card and the digits carry no
/// pitch meaning.
@immutable
class CodeEntry {
  const CodeEntry({required this.code, required this.call});

  final String code;

  /// Null for a decoy cell — mapped to no call. Out of scope for M1; the shape
  /// is here because §10.2 defines it and leaving it out would invite a schema
  /// change later.
  final Call? call;
}

/// A generated wristband card (§10.2).
///
/// Generation and print are M2. What M1 needs is the *lookup* contract: which
/// codes exist for a call, and how one is chosen when the coach taps.
@immutable
class WristbandCard {
  const WristbandCard({
    required this.id,
    required this.label,
    required this.entries,
    required this.codesPerCall,
  });

  /// Generates a card covering every callable (type × zone) in [config].
  ///
  /// Real generation is M2 and will lay cells out for a physical window; this
  /// assigns coordinates in order and shuffles the contents, which is enough to
  /// exercise lookup and to make the card's *size* visible — the cell count is
  /// the sum over types of that type's zone count × k, never the cross product
  /// (§10.1).
  ///
  /// Throws [ArgumentError] when that count exceeds the 810 cells three digits
  /// can address (§10.2).
  factory WristbandCard.forConfig(
    TeamCallConfig config, {
    required Random random,
    int codesPerCall = 4,
    String id = 'stub-card',
    String label = 'Stub card',
  }) {
    final calls = <Call>[
      for (final type in config.arsenal)
        for (final zone in config.callableZones(type.id))
          Call(pitchTypeId: type.id, zoneId: zone.id),
    ];

    final slots = <Call>[
      for (final call in calls) ...List.filled(codesPerCall, call),
    ]..shuffle(random);

    // §10.2's grid-coordinate model: first digit is the row, the rest the
    // column label. The row digit is single, so the card is at most nine rows
    // deep and the columns are however many it takes to hold the calls,
    // filling rows first so a card of any size uses the whole row range. The
    // rows are the entire reason lookup is O(1) — a pitcher finds row 5, then
    // scans that row for column 39.
    const rowCount = 9;
    const maxColumnCount = 90;
    final columnCount = (slots.length / rowCount).ceil();

    // Three digits address 9 rows x 90 columns and no more, so 810 cells is the
    // format's ceiling and §10.2 makes enforcing it the generator's job. Say so
    // here: past the ceiling the label pool below runs out, which would surface
    // as a RangeError on the 91st column with nothing in it a coach could act
    // on.
    if (columnCount > maxColumnCount) {
      throw ArgumentError.value(
        codesPerCall,
        'codesPerCall',
        'card needs ${slots.length} cells (${calls.length} calls x '
            '$codesPerCall) but the three-digit format addresses at most '
            '${rowCount * maxColumnCount} (§10.2) — lower k, or narrow the '
            'callable zones',
      );
    }

    // Column labels are drawn from the whole two-digit range rather than
    // running 10, 11, 12… Contiguous labels make every code on an 80-cell card
    // read as "a row digit plus something in the teens," which is a pattern
    // worth denying anyone listening — and it costs nothing, because the
    // labels are printed across the top of the card either way. Sorted, so
    // scanning a row stays monotonic and the lookup is no slower.
    final labels = (List.generate(
      maxColumnCount,
      (i) => i + 10,
    )..shuffle(random)).take(columnCount).toList()..sort();

    final entries = <CodeEntry>[];
    for (var i = 0; i < slots.length; i++) {
      final row = (i ~/ columnCount) + 1;
      final column = labels[i % columnCount];
      entries.add(CodeEntry(code: '$row$column', call: slots[i]));
    }

    return WristbandCard(
      id: id,
      label: label,
      entries: entries,
      codesPerCall: codesPerCall,
    );
  }

  final String id;
  final String label;
  final List<CodeEntry> entries;

  /// §10.2's `k`, default 4: every call gets multiple codes so the same call is
  /// 539 one pitch and 217 three pitches later. This is the sign-stealing
  /// defense, and it beats a static laminated sheet, where pattern-hunting
  /// parents in the stands are a real thing.
  ///
  /// Nothing reads it yet — not even the tests, which pass `k` to
  /// [WristbandCard.forConfig] and then count entries. It is carried because a
  /// card that cannot say what k it was cut at can't be reprinted or
  /// regenerated at the same k (M2), and because §10.2's per-call k lands here
  /// as the thing this field generalizes.
  final int codesPerCall;

  /// Every code mapped to [call]. Empty when the card cannot express it — the
  /// call screen must then not offer it (§10.1), since a code the coach yells
  /// has to be a code the pitcher can look up.
  List<String> codesFor(Call call) => [
    for (final entry in entries)
      if (entry.call == call) entry.code,
  ];

  bool canExpress(Call call) => codesFor(call).isNotEmpty;
}

/// Picks which of a call's codes to speak.
///
/// Stateful on purpose: §10.2 requires never repeating the code just used for
/// the *same* call, which needs memory of the last one per call. Different
/// calls are independent — reusing a code for a different call is fine and
/// unavoidable.
class CodeSelector {
  CodeSelector({required this.card, Random? random})
    : _random = random ?? Random();

  final WristbandCard card;
  final Random _random;
  final Map<Call, String> _lastUsed = {};

  /// A code for [call], or null when the card cannot express it.
  ///
  /// Never the code just used for this same call, provided the card offers more
  /// than one — with k = 1 there is nothing to rotate to, and repeating is
  /// better than refusing to give the coach a code.
  String? next(Call call) {
    final codes = card.codesFor(call);
    if (codes.isEmpty) return null;

    final last = _lastUsed[call];
    final choices = codes.length > 1
        ? (codes.where((code) => code != last).toList())
        : codes;

    final picked = choices[_random.nextInt(choices.length)];
    _lastUsed[call] = picked;
    return picked;
  }

  /// Re-roll (§10.3's swipe): a different code for the same call, without
  /// re-tapping. Identical to [next] — the no-repeat rule already guarantees
  /// the code changes — and named separately because the call site means
  /// something different by it.
  String? reroll(Call call) => next(call);
}
