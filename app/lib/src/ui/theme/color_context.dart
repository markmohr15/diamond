import 'package:flutter/foundation.dart';

/// Whose color currently fills the single accent slot (§23.1.2, §23.3).
///
/// A *value*, not a boolean and not a live-game flag: context follows
/// attention, not game state (§23.3). A scouting report read on Tuesday themes
/// exactly as the live game against that team does on Saturday, and nothing
/// about being mid-game changes the accent by itself.
///
/// - [ownTeam] — browsing: the schedule, any list showing more than one
///   opponent, own-team stats, roster, settings, onboarding.
/// - [ColorContext.opponent] — one team has your attention: their hitter cards
///   and detail (§18.1), their book and history, the due-batter deck scoped to
///   them (§18.2), and scoring a game against them.
@immutable
sealed class ColorContext {
  const ColorContext();

  /// Scoped to one opponent. [teamId] is the record's id, not its color —
  /// color is data resolved at read time (§23.3), never carried in the state.
  const factory ColorContext.opponent(String teamId) = OpponentContext;

  /// The default everywhere after onboarding.
  static const ColorContext ownTeam = OwnTeamContext();
}

final class OwnTeamContext extends ColorContext {
  const OwnTeamContext();

  @override
  bool operator ==(Object other) => other is OwnTeamContext;

  @override
  int get hashCode => (OwnTeamContext).hashCode;

  @override
  String toString() => 'ColorContext.ownTeam';
}

final class OpponentContext extends ColorContext {
  const OpponentContext(this.teamId);

  final String teamId;

  @override
  bool operator ==(Object other) =>
      other is OpponentContext && other.teamId == teamId;

  @override
  int get hashCode => Object.hash(OpponentContext, teamId);

  @override
  String toString() => 'ColorContext.opponent($teamId)';
}
