# Diamond — CLAUDE.md

Diamond is a tablet-first (phone-capable) baseball/fastpitch-softball coaching app: live pitch-by-pitch
scoring with pitch calling (wristband codes), pitch locations (intended AND actual), batted-ball
coordinates including fouls, misplay/error tracking, scouting books with heat maps and spray charts,
and full stats — all offline-first. Built by Mark (senior dev, architect/reviewer) with Claude Code.

**The full spec is `docs/spec.md` (v0.42). It is authoritative. When this file and the spec disagree,
the spec wins; flag the discrepancy.** Section references below (§N) point into that document.

## Architecture in five sentences

1. A game is an **append-only stream of atomic events** (§1–§7). Events are never mutated; corrections
   append (`corrects`), undo appends (`VoidEvent`). Plays are sequences of atomic events, never templates.
2. **Everything else is a projection**: count, outs, score, box score, stats, heat maps, official errors,
   earned runs — pure functions folding the stream (§5, §13, §17). Storing derived state in events is a bug.
3. **Offline-first is the prime directive**: all projections run on-device against Drift/SQLite. No feature
   may require connectivity to record or view anything during a game (§12.6, §19.1, §21.5).
4. The scorer records **physics, not rulings** (§13): touch types are physical (`dropped`, `booted`,
   `wild_throw`…); official error charging, hit-vs-error, and earned runs are derived, gated by one
   scorer-judgment flag (`ordinaryEffort`).
5. Multi-device uses **disjoint streams** (primary scores; secondaries annotate) so sync is a conflict-free
   set union over pluggable transports (§12).

## Non-negotiables (§21.5) — CI enforces these

- The event schema is defined **once** in `schema/` (JSON Schema) and code-generated into Dart and TS.
  Hand-written duplicate types are a build failure. Schema change protocol: edit schema → regenerate both
  targets → update fixtures/tests → one atomic commit.
- `fixtures/plays/*.json` (§14 acceptance plays) must pass in the Dart rules engine (and any server-side
  validation) at all times. New weird plays become new fixtures, never special cases in code.
- Anything computing a stat outside the projection engine is a bug.
- The count/outs/base state is **never wrong** in real games (§11.2). Uncertainty is surfaced visually (count HUD renders amber when an `unknown` pitch makes the count ambiguous) and
  resolved via `CountCorrection` checkpoints (§12.5) — never guessed.
  ObservationSessions (§19.5) explicitly relax this.

## Repo map

```
docs/spec.md        authoritative spec (v0.42)
docs/spec-history.md  version history; the spec's status line keeps only the last three
schema/             JSON Schema source of truth (common/ + events/)
tools/codegen/      schema → Dart + TS generation (see its README)
app/                Flutter app (created by ticket DIA-001; Drift, rules engine, projections, UI)
server/             Node/Express + Postgres (Milestone 2+; thin auth/ingest/relay only)
fixtures/plays/     §14 acceptance plays as language-neutral JSON fixtures
tickets/            markdown tickets; work them in ID order unless told otherwise
```

## Stack & conventions (§21)

- **App:** Flutter/Dart, Drift (SQLite). State mgmt: Riverpod. Custom-drawn UI (`CustomPaint`) for zone
  canvas, field canvas, call grid, heat maps — no platform-widget lookalikes needed.
- **Server:** Node 20+/Express/TypeScript, Postgres (JSONB payloads). It is a thin service: auth,
  membership, event ingest, websocket fan-out. If server code starts computing stats, stop — that's
  the app's projection engine's job.
- **Coordinates:** `ZoneCoord` normalized, catcher's view, absolute x (flip by handedness at render, §3.1).
  `FieldCoord` in absolute feet, home plate origin, θ=0 at CF (§3.2). Never clamp foul territory.
- **`ZoneCoord`'s two axes have different scales** (§3.1): x normalizes against the fixed 17″ plate, y
  against *this batter's* zone height. The frontal-plane render ratio is `8.5″ / zoneHeight` (0.354 at the
  canonical 12U profile, 0.425 at 10U) and the ground plane is derived (`y_ground` = −0.646 at 12U), not a
  layout choice. Rendering both axes at equal pixels-per-unit is wrong by ~2.8×; hardcoding any single
  ratio is wrong as soon as a second batter exists (§11.4).
- **Geometric figures in prose are rounded for display; compute from §3.1's canonical inputs.**
- Dart: `very_good_analysis` lints. TS: strict mode, eslint. Tests colocated per package convention.
- **US spelling throughout** — `color`, never `colour`; likewise behavior, normalize, canceled. Applies to
  prose as well as identifiers: comments, doc comments, tickets, commit messages, and PR bodies. The APIs
  being described are US-spelled (`Color`, `ColorScheme`), so British prose reads as inconsistent with the
  code it documents.
- A method/field used only by the test suite (not by any production code path) gets a doc comment saying so at its definition.
- Commits: conventional-ish, reference ticket IDs (e.g., `feat(rules): DIA-004 plays 01-03 passing`).
- **Spec changes touch three places, always:** bump the version in `docs/spec.md`'s header; add the full
  entry to `docs/spec-history.md` (newest first); and add a one-line summary to the spec's status line,
  dropping the oldest of the three it carries. The status line holds exactly three entries — never append a
  fourth — and the history file holds all of them. Then update the two version references in this file.

## Working agreements with Mark

- Mark reviews plans before large edits — propose, then build. Prefer vertical slices.
- When a design question isn't answered by the spec, say so and ask; don't invent product decisions.
- Writing or modifying code requires an explicit go-ahead from Mark. The ONLY approval phrases are: "approved", "go ahead", or "proceed". Nothing else is approval — not silence, not questions, not "makes sense", not discussion of your plan, not agreement with parts of it.
- If Mark's reply contains ANY change, correction, or new requirement, the previous approval is REVOKED. Restate the amended plan (delta only, briefly) and wait for a fresh approval phrase.
- Approval covers exactly the stated plan. Discovering mid-build that the plan must change — new refactor, new schema edit, new dependency, scope growth — means STOP and re-propose the delta before continuing.
- Exempt (no approval needed): reading files, running existing tests, searches, and answering questions. When unsure whether something needs approval, ask — asking is always free.
- UI work follows the design language (§18.7): data-ink first, one accent, accent on the datum not the frame, sunlight-glanceable, every number shows its denominator, no decorative motion. "Serviceable" is the failure bar.
- Softball vs. baseball differences always route through `RuleSet` — never `if (softball)` scattered in logic (§1, §4.4).
- Youth-athlete data is sensitive: team-private by default, no sharing features without explicit design (§19.5). Never log player names in telemetry.

## Git workflow

- NEVER commit directly to `main`. Every ticket gets a branch: `dia-NNN-short-slug`
  (e.g., `dia-002-codegen`). One ticket = one branch = one PR.
- Open the PR with `gh pr create` when work begins (draft) or completes. PR title:
  `DIA-NNN: <ticket title>`. Body: plan summary, spec sections consulted, how to test,
  and anything that deviates from the ticket (flagged prominently).
- Mark merges PRs. Never merge, never force-push, never rebase `main`.
- Never use --no-verify or --force on any git operation.
- Keep PRs ticket-sized. If a ticket grows past ~600 lines of meaningful diff, stop and propose splitting it.
- Before any commit, verify the current branch is dia-NNN-*; if on main, stop and create the ticket branch first — moving uncommitted work to a new branch is always the correct fix.

## Milestone 1 (current)

**Score a half-inning of one game, locally, no backend:** event store + projection engine + rules engine
passing all play fixtures + scoring overrides + zone canvas + pitch bounce capture + call screen + pitch
loop + field canvas subset + one scripted end-to-end half-inning test. Tickets DIA-001 … DIA-011. Server
work is out of scope until M2.
