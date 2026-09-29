/// DIA-024: what a play scored as, said in a sentence.
///
/// A projection over [OfficialScoring], computing nothing of its own (§21.5)
/// — every ruling it reads is already derived, and this only chooses words
/// for it. The scorer has never been able to see what her entry became;
/// through the 2026-09-04 simulator session, checking meant reading
/// `diamond.sqlite` and folding the stream by hand.
library;

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/field/spray_sector.dart';
import 'package:diamond/src/rules/official_scoring.dart';

/// One happening, as one or more sentences.
class PlayLine {
  const PlayLine({required this.pitchEventId, required this.sentences});

  final String pitchEventId;

  /// **One sentence per cause** — the batted ball is one, each charged
  /// misplay is another. Two misplays therefore read as two errors rather
  /// than one invented N-base error, which is the distinction DIA-022
  /// settled at entry and this says out loud.
  final List<String> sentences;

  String get text => sentences.join(' ');
}

/// How a player is named. Defaults to her id, which is all the system has:
/// there is no roster, so `LineupSet.battingOrder` is opaque strings.
/// Identity belongs to roster building (Mark, 2026-09-29); this seam exists
/// so that work supplies names without rewriting a single line of grammar.
typedef PlayerLabel = String Function(String playerId);

String _asIs(String playerId) => playerId;

/// The half-inning, in order, skipping the pitches that were only pitches.
List<PlayLine> playLines(
  OfficialScoring scoring, {
  PlayerLabel label = _asIs,
}) => [
  for (final play in scoring.plays)
    if (!play.isEmpty)
      if (_sentences(play, scoring, label) case final said when said.isNotEmpty)
        PlayLine(pitchEventId: play.pitchEventId, sentences: said),
];

List<String> _sentences(
  PlayRecord play,
  OfficialScoring scoring,
  PlayerLabel label,
) {
  final charged = {for (final e in scoring.errors) e.touchEventId: e};
  // Legs group by what caused them: unattributed movement belongs to the
  // batted ball's sentence, and a leg linked to a *charged* misplay belongs
  // to that misplay's. A misplay nobody linked to anything charges nothing
  // and gets no sentence — it cost nothing to say.
  final byCause = <String?, List<({String eventId, RunnerAdvance payload})>>{};
  for (final a in play.advances) {
    final enabler = a.payload.enabledByTouchId;
    byCause
        .putIfAbsent(charged.containsKey(enabler) ? enabler : null, () => [])
        .add(a);
  }

  // A foul ball is not a happening. It earns a line only when something was
  // charged on it — a dropped foul pop — and then the error sentence is the
  // whole story, so describing the pop first would say it twice.
  final fair = play.ballInPlay?.payload.fair ?? false;
  final sentences = <String>[
    if (play.ballInPlay != null) ...[
      if (fair) _battedBall(play, scoring, label, byCause[null] ?? const []),
    ] else
      ..._betweenPitches(play, label, byCause[null] ?? const []),
  ];

  for (final touch in play.touches) {
    final error = charged[touch.eventId];
    if (error == null) continue;
    final caused = byCause[touch.eventId] ?? const [];
    final who = positionAbbreviations[error.position] ?? '${error.position}';

    // An error that bought no base still has to be said. A dropped foul pop
    // charges on `prolongedAtBat` — there is no leg to hang it off, and
    // skipping it made the whole play read as an uneventful pop-up.
    if (caused.isEmpty) {
      if (error.basis != OfficialErrorBasis.prolongedAtBat) continue;
      final noun = _trajectoryNouns[play.ballInPlay?.payload.trajectory];
      sentences.add(
        '${label(play.batterId)} remained at bat on a dropped '
        '${noun ?? 'ball'} error by the $who.',
      );
      continue;
    }

    // Surviving where she already stood is not an advance — §4.3 reserves
    // from==to for exactly this — so it does not read as one.
    final settled = _finalLegs(caused);
    for (final a in settled.where((a) => a.payload.from == a.payload.to)) {
      final what = _touchNouns[touch.payload.touchType] ?? 'misplay';
      sentences.add(
        '${label(a.payload.runnerId)} safe at '
        '${_baseName(a.payload.to)} on a $what by the $who.',
      );
    }

    final moved = [
      for (final a in settled)
        if (a.payload.from != a.payload.to) _advanceClause(a.payload, label),
    ];
    if (moved.isEmpty) continue;
    sentences.add(
      'On a ${error.kind.name} error by the $who, ${_andJoin(moved)}.',
    );
  }
  return sentences;
}

/// The hit when it was one, the trajectory when it was not — and the hit
/// verb already says where she ended up, which is why only the second kind
/// needs a destination clause at the end.
const _hitVerbs = {
  'single': 'singled',
  'double': 'doubled',
  'triple': 'tripled',
  'home_run': 'homered',
};

/// Caught, and the batter retired on it. The catch is the out, so the verb
/// says both.
const _caughtVerbs = {
  Trajectory.FLY: 'flew out',
  Trajectory.LINE: 'lined out',
  Trajectory.POPUP: 'popped out',
  Trajectory.GROUND: 'grounded out',
  Trajectory.BUNT: 'bunted out',
};

const _trajectoryVerbs = {
  Trajectory.GROUND: 'grounded',
  Trajectory.LINE: 'lined',
  Trajectory.FLY: 'flied',
  Trajectory.POPUP: 'popped',
  Trajectory.BUNT: 'bunted',
};

String _battedBall(
  PlayRecord play,
  OfficialScoring scoring,
  PlayerLabel label,
  List<({String eventId, RunnerAdvance payload})> plain,
) {
  final bip = play.ballInPlay!.payload;
  final outcome = play.plateAppearanceIndex >= 0
      ? scoring.batterOutcomes[play.plateAppearanceIndex]
      : null;
  final batter = label(play.batterId);
  final hitVerb = outcome != null && outcome.hit
      ? _hitVerbs[outcome.scoring]
      : null;

  // Caught, and she is out on it: the verb carries the out, so the clause
  // that would have repeated it ("out at first") comes off. Mark: *"Jones
  // flew out to CF."*
  final retired = play.outs
      .where((o) => o.payload.runnerId == play.batterId)
      .firstOrNull;
  final caught = retired?.payload.how == How.FLY_OUT ? retired : null;
  // A sacrifice fly says so, and the trajectory stops mattering: §13.6
  // credits one for any ball caught in the air, so play-10's line drive is
  // a sacrifice fly too. Where it does not derive as one, the plain verb
  // stands — *flew out to CF, Jones advanced to third*.
  //
  // §13.6 knows two sacrifices, and the catch tells them apart: caught in
  // the air is the fly, anything else is the bunt. Either way the verb
  // phrase carries the out and the base goes unsaid — first is implied,
  // the same way it is in *grounded out to SS* (Mark, 2026-09-30).
  final sacrifice = outcome?.sacrifice ?? false;
  final sacrificed = sacrifice && retired != null;
  final verb = sacrificed
      ? 'out on a sacrifice ${caught != null ? 'fly' : 'bunt'}'
      : caught != null
      ? (_caughtVerbs[bip.trajectory] ?? 'flew out')
      : (hitVerb ?? _trajectoryVerbs[bip.trajectory] ?? 'hit');

  // **The infield is named by its fielder, the outfield by its sector** —
  // which is how it is said: *grounded to SS*, but *doubled to left*, never
  // "doubled to LF". So the first touch names the place only when an
  // infielder made it; past that the bearing does, and a ball nobody
  // touched is an outfield ball by definition, since in the infield
  // somebody picks it up eventually (Mark, 2026-09-29).
  //
  // A **catch** is the exception to both: it is something a fielder did
  // rather than somewhere the ball came down, so it names her wherever she
  // was standing — *flew out to CF*, never "flew out to center".
  final first = play.touches.isEmpty ? null : play.touches.first.payload;
  final byFielder = first != null && (caught != null || first.position <= 6);
  final place = byFielder
      ? (positionAbbreviations[first.position] ?? '${first.position}')
      : sectorFor(bip.landing).label;

  final clauses = <String>['$batter $verb to $place'];
  for (final out in play.outs) {
    // Her own out is already in the verb when the catch or the sacrifice
    // said it; repeating it as "out at first" is the clause Mark cut.
    if (identical(out, retired) && (caught != null || sacrificed)) continue;
    clauses.add(_outClause(out.payload, outcome, label));
  }
  for (final a in _finalLegs(plain)) {
    if (a.payload.runnerId == play.batterId) continue;
    // A runner who ended where she began did not do anything worth a
    // clause — unless a misplay is why, and that has its own sentence.
    if (a.payload.from == a.payload.to) continue;
    clauses.add(_advanceClause(a.payload, label));
  }
  // Her own destination, only when the verb has not already implied it.
  if (hitVerb == null) {
    final own = plain.where((a) => a.payload.runnerId == play.batterId);
    for (final a in own) {
      clauses.add('$batter to ${_baseName(a.payload.to)}');
    }
  }
  return '${_join(clauses)}.';
}

/// §15.6's happenings. Each is one clause about the ball and then whoever
/// moved on it.
List<String> _betweenPitches(
  PlayRecord play,
  PlayerLabel label,
  List<({String eventId, RunnerAdvance payload})> plain,
) {
  final clauses = <String>[];
  for (final out in play.outs) {
    clauses.add(switch (out.payload.how) {
      // No "at": she is caught stealing *second*, picked off *first* — the
      // base is the thing she was going to or standing on, not a place the
      // out happened (Mark, 2026-09-29).
      How.CAUGHT_STEALING =>
        '${label(out.payload.runnerId)} caught stealing '
            '${_baseName(out.payload.atBase)}',
      How.PICKED_OFF =>
        '${label(out.payload.runnerId)} picked off '
            '${_baseName(out.payload.atBase)}',
      How.LEFT_EARLY => '${label(out.payload.runnerId)} out, left early',
      _ => _outClause(out.payload, null, label),
    });
  }
  // The getaway is a property of the pitch, so it leads — "Wild pitch,
  // Simmons advanced to third" rather than hanging it off her.
  final getaway = plain
      .map((a) => a.payload.reason)
      .where(
        (r) =>
            r == RunnerAdvanceReason.WILD_PITCH ||
            r == RunnerAdvanceReason.PASSED_BALL,
      )
      .firstOrNull;
  // The batter leads when she is in it: *Jones reached on catcher's
  // interference, Simmons advanced to second* — the award is hers and the
  // forced runner follows from it.
  final ordered = [...plain]
    ..sort((a, b) {
      final aFirst = a.payload.runnerId == play.batterId ? 0 : 1;
      final bFirst = b.payload.runnerId == play.batterId ? 0 : 1;
      return aFirst.compareTo(bFirst);
    });
  final moved = [
    for (final a in _finalLegs(ordered))
      switch (a.payload.reason) {
        RunnerAdvanceReason.STOLEN_BASE =>
          '${label(a.payload.runnerId)} stole ${_baseName(a.payload.to)}',
        RunnerAdvanceReason.DEFENSIVE_INDIFFERENCE =>
          '${_advanceClause(a.payload, label)} on defensive indifference',
        _ => _advanceClause(a.payload, label),
      },
  ];
  final lead = switch (getaway) {
    RunnerAdvanceReason.WILD_PITCH => 'Wild pitch',
    RunnerAdvanceReason.PASSED_BALL => 'Passed ball',
    _ => null,
  };
  final all = [if (lead != null) lead, ...clauses, ...moved];
  return all.isEmpty ? const [] : ['${_join(all)}.'];
}

/// One clause per runner, naming where she ended up.
///
/// A runner can take two bases on one ball — §14 play-15's wild pitch moves
/// her second to third to home — and that is two legs but one thing that
/// happened to her. Only her last one is said.
///
/// Scoped to a single cause, which is what keeps *Simmons advanced to
/// second. On a fielding error by the LF, Simmons advanced to third* intact:
/// those are two causes and genuinely two sentences.
List<({String eventId, RunnerAdvance payload})> _finalLegs(
  List<({String eventId, RunnerAdvance payload})> legs,
) {
  final last = <String, ({String eventId, RunnerAdvance payload})>{};
  for (final leg in legs) {
    final held = last[leg.payload.runnerId];
    if (held == null || leg.payload.to > held.payload.to) {
      last[leg.payload.runnerId] = leg;
    }
  }
  // First-appearance order: the runners are named in the order they moved.
  final seen = <String>{};
  return [
    for (final leg in legs)
      if (seen.add(leg.payload.runnerId)) last[leg.payload.runnerId]!,
  ];
}

String _advanceClause(RunnerAdvance a, PlayerLabel label) {
  final who = label(a.runnerId);
  final where = a.to == 4
      ? '$who scored'
      : '$who advanced to ${_baseName(a.to)}';
  return switch (a.reason) {
    // The award names itself; without it the line says she moved and never
    // says why anyone was charged for it.
    RunnerAdvanceReason.OBSTRUCTION => '$where on obstruction',
    RunnerAdvanceReason.CATCHER_INTERFERENCE when a.from == 0 =>
      "$who reached on catcher's interference",
    // Two facts, and a scorer wants both: the strikeout is hers either way,
    // and how she reached is a separate question §4.3's `cause` answers
    // (v0.50). Absent a cause she beat the throw, or reached on an error
    // that `enabledByTouchId` names in its own sentence.
    RunnerAdvanceReason.DROPPED_THIRD_STRIKE => switch (a.cause) {
      Cause.WILD_PITCH => '$who struck out, reached first on a wild pitch',
      Cause.PASSED_BALL => '$who struck out, reached first on a passed ball',
      null => '$who struck out, reached first',
    },
    _ => where,
  };
}

String _outClause(RunnerOut out, BatterOutcome? outcome, PlayerLabel label) {
  // The ball found her; there is no base to name, and no fielder made a
  // play. Mark: *"Simmons out advancing."*
  if (out.how == How.BATTED_BALL_CONTACT) {
    return '${label(out.runnerId)} out advancing';
  }
  final base = '${label(out.runnerId)} out at ${_baseName(out.atBase)}';
  // Said once, on the out that earned it: the batter reached because the
  // defense took somebody else.
  return outcome?.scoring == 'fielders_choice'
      ? "$base on a fielder's choice"
      : base;
}

/// What the ball was, as a noun — for sentences that describe the ball
/// rather than the swing that produced it.
const _trajectoryNouns = {
  Trajectory.GROUND: 'ground ball',
  Trajectory.LINE: 'line drive',
  Trajectory.FLY: 'fly ball',
  Trajectory.POPUP: 'pop up',
  Trajectory.BUNT: 'bunt',
};

/// The misplay itself, named rather than classified: where nobody advanced,
/// *a missed catch by the 2B* says more than *a catching error*.
const _touchNouns = {
  TouchType.DROPPED: 'dropped ball',
  TouchType.BOBBLED: 'bobble',
  TouchType.BOOTED: 'boot',
  TouchType.WILD_THROW: 'wild throw',
  TouchType.MISSED_CATCH: 'missed catch',
  TouchType.TAG_MISSED: 'missed tag',
};

const _baseNames = {1: 'first', 2: 'second', 3: 'third', 4: 'home'};

String _baseName(int base) => _baseNames[base] ?? '$base';

/// The batted ball's clauses run on commas — *Jones grounded to SS, Simmons
/// out at second, Jones to first* — because each is a separate thing that
/// happened rather than a list being enumerated.
String _join(List<String> parts) => parts.join(', ');

/// An error's consequences are a list, and read as one: *Simmons scored and
/// Jones advanced to third*.
String _andJoin(List<String> parts) {
  if (parts.length <= 1) return parts.join();
  return '${parts.sublist(0, parts.length - 1).join(', ')} '
      'and ${parts.last}';
}
