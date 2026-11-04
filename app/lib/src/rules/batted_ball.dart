import 'package:diamond/src/events/generated/events.dart';

/// What a batted ball's trajectory says, asked in one place so the rules
/// engine, official scoring, the play log and the entry surface cannot
/// disagree about it.

/// Trajectories that leave the bat in the air: a fielder can catch one, a
/// catch retires the batter, and a drop is a drop. An air bunt is one of
/// them (DIA-019 M) — it can be caught like any pop-up.
const _airborne = {
  Trajectory.FLY,
  Trajectory.POPUP,
  Trajectory.LINE,
  Trajectory.BUNT_AIR,
};

/// Whether [trajectory] left the bat in the air.
bool isAirborne(Trajectory? trajectory) => _airborne.contains(trajectory);

/// Whether she bunted (§13.6): on the ground or in the air, it is a bunt
/// for the sacrifice whichever way it went.
bool isBunt(Trajectory? trajectory) =>
    trajectory == Trajectory.BUNT || trajectory == Trajectory.BUNT_AIR;
