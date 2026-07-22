# Schema codegen

`schema/` is the single source of truth (CLAUDE.md non-negotiable #1). `npm run codegen`
(from the repo root, or `npm run codegen` inside this directory) generates:

- Dart types → `app/lib/src/events/generated/events.dart`
- TypeScript types → `server/src/events/generated/events.ts`

Both files are one combined output per target: `envelope.schema.json` + every
`schema/events/*.schema.json` file, generated in a single `quicktype` invocation per
language so shared `$ref` types (`ZoneCoord`, `FieldCoord`) are deduplicated instead of
being redefined in every file that references them. `schema/common/*.schema.json` files
are never passed as direct inputs — they're pulled in automatically via `$ref`.

## Decision: quicktype, not a custom generator

DIA-002 evaluated both, per the ticket. A hand-written generator was the a priori lean
(full control over enum casing and output determinism), but an empirical spike reversed
that: quicktype resolves `$ref`s correctly, dedupes shared types across a multi-file
invocation, produces byte-identical output across repeated runs, and — critically — its
enum round-trip does not depend on target-language member naming at all. Both targets
generate an explicit string-keyed value map (Dart's `EnumValues` class; TypeScript's
literal union types are the wire values directly), so snake_case fidelity holds regardless
of how a member gets named. That fully addresses the concern that motivated considering a
custom generator in the first place.

The one real friction found: quicktype's Dart target renders enum members as
`SCREAMING_SNAKE_CASE` (e.g. `FAKE_SLAP`) with no CLI flag to change it (other quicktype
targets have `--enumerator-style`; Dart doesn't). Rather than write ~200 lines of generator
to avoid one lint rule, `app/analysis_options.yaml` excludes
`lib/src/events/generated/**` from analysis entirely — generated code isn't hand-maintained
and isn't held to our lint conventions.

## Invoking quicktype — pinned, local install only, never `npx`

`quicktype` is an exact-pinned `devDependency` of `tools/codegen/package.json` (no `^`or
`~` range). `generate.mjs` shells out to `tools/codegen/node_modules/.bin/quicktype`
directly — **never** `npx quicktype`. Bare `npx` can silently resolve to whatever version
is cached or latest-on-registry if the local copy isn't found, which would make generated
output drift with upstream quicktype releases independent of any commit in this repo — a
determinism hole in exactly the place the CI drift-check is supposed to guard.

**Upgrading quicktype (deliberate, not automatic):**

1. `cd tools/codegen && npm view quicktype version` to see the latest release.
2. Update the exact version pin in `tools/codegen/package.json`, then `npm install`
   (this updates `package-lock.json` too — commit it alongside).
3. `npm run codegen` from the repo root and inspect the diff in
   `app/lib/src/events/generated/events.dart` and `server/src/events/generated/events.ts`
   closely — a quicktype version bump is the only thing that can change generated output
   without a `schema/` change, so review it like a dependency upgrade, not a schema edit.
4. Run `flutter analyze`, `flutter test` (app), and `npm run typecheck` (server) to confirm
   nothing broke.
5. Commit the `package.json`/`package-lock.json` bump and the regenerated files together,
   in one commit, separate from any unrelated schema changes.

## TypeScript target: no `--just-types`

Deliberately not using `--just-types` for the TypeScript output. With it, quicktype
statically types `wallClock` as `Date` but strips the `Convert` functions that actually
construct one — `JSON.parse` still hands back a `string` at runtime, so the type lies.
Without `--just-types`, quicktype keeps its `Convert.toX`/`xToJson` transform functions,
which do the real date parsing and also give the server free runtime shape-validation at
the event-ingest boundary (consistent with CLAUDE.md's "thin ingest" description of the
server). Dart is unaffected either way — its generated `fromJson`/`toJson` always do real
`DateTime.parse`/`toIso8601String()` regardless of this flag.

## Gotcha: generated `toJson()` emits `null` for unset optionals — never store that as-is

Generated `toJson()` (Dart and TS both) always writes every key, using `null` for optional
fields that weren't set, rather than omitting the key. Our schemas never permit an explicit
`null` for these fields (they're plain `{"type": "string"}` etc., not nullable unions) — the
schema's actual convention is "omit the key entirely" for "not captured." A payload map with
`"fielderId": null` written to the event store is schema-invalid, even though it came out of
a generated `toJson()` call.

**Whenever future code builds an event payload via `SomeType(...).toJson()` for storage or
the wire (DIA-006/007 will be the first), strip null-valued keys before persisting it.**
`app/test/events/generated_types_test.dart` demonstrates the pattern: filter
`.entries.where((e) => e.value != null)` before comparing/storing. This isn't a quicktype
bug to work around in the generator — it's a boundary concern for whoever writes JSON out.

## Requirements this must keep holding

- `npm run codegen` regenerates both targets deterministically (verified: running it twice
  produces byte-identical output).
- Generated files are COMMITTED. CI runs codegen and fails on `git diff --exit-code`
  (drift check).
- Enum values round-trip exactly (snake_case wire format preserved) — verified by
  `app/test/events/generated_types_test.dart`, which parses every `fixtures/plays/*.json`
  event payload through the generated Dart types and deep-equals the re-serialized result
  against the original.
