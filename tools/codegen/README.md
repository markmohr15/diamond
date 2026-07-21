# Schema codegen

`schema/` is the single source of truth (CLAUDE.md non-negotiable #1). This tool generates:
- Dart types → `app/lib/src/events/generated/`
- TypeScript types → `server/src/events/generated/`

Ticket DIA-002 wires this for real. Approach (validate during the ticket, choose the better):
1. `quicktype` (npx, no install friction) driving both targets from the JSON Schemas, or
2. a small custom generator (the schemas are simple: objects, enums, refs) if quicktype's Dart
   output fights Drift/freezed conventions.

Requirements regardless of approach:
- `npm run codegen` regenerates both targets deterministically.
- Generated files are COMMITTED. CI runs codegen and fails on `git diff --exit-code` (drift check).
- Enum values must round-trip exactly (snake_case wire format preserved).
