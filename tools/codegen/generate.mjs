// schema/*.schema.json -> Dart (app) + TS (server) types, via the pinned local
// quicktype install (never npx — see README's "upgrading quicktype" section for why).
//
// Inputs:  ../../schema/envelope.schema.json, ../../schema/events/*.schema.json
//          (schema/common/*.schema.json are pulled in automatically via $ref —
//          they are never passed as direct inputs, or quicktype would also emit
//          them as spurious top-level types)
// Outputs: ../../app/lib/src/events/generated/events.dart
//          ../../server/src/events/generated/events.ts
// Contract: deterministic; committed; CI drift-checks with `git diff --exit-code`.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '../..');
const schemaEventsDir = path.join(repoRoot, 'schema/events');
const quicktypeBin = path.join(here, 'node_modules/.bin/quicktype');

if (!fs.existsSync(quicktypeBin)) {
  console.error(
    'quicktype binary not found — run `npm install` in tools/codegen first ' +
      '(it must come from the pinned local devDependency, never npx).',
  );
  process.exit(1);
}

const schemaFiles = [
  path.join(repoRoot, 'schema/envelope.schema.json'),
  ...fs
    .readdirSync(schemaEventsDir)
    .filter((f) => f.endsWith('.schema.json'))
    .sort()
    .map((f) => path.join(schemaEventsDir, f)),
];

const banner = (lang) =>
  `// GENERATED FILE — DO NOT EDIT.\n` +
  `// Source of truth: schema/ (envelope.schema.json + schema/events/*.schema.json).\n` +
  `// Regenerate with \`npm run codegen\` from the repo root. See tools/codegen/README.md.\n\n`;

function runQuicktype(lang, outFile) {
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  execFileSync(
    quicktypeBin,
    ['--src-lang', 'schema', '--lang', lang, '-o', outFile, ...schemaFiles],
    { stdio: 'inherit' },
  );
  const generated = fs.readFileSync(outFile, 'utf8');
  fs.writeFileSync(outFile, banner(lang) + generated);
}

runQuicktype('dart', path.join(repoRoot, 'app/lib/src/events/generated/events.dart'));
runQuicktype('typescript', path.join(repoRoot, 'server/src/events/generated/events.ts'));

console.log('codegen: wrote app/lib/src/events/generated/events.dart');
console.log('codegen: wrote server/src/events/generated/events.ts');
