# Acceptance play fixtures (spec §14)

Language-neutral test fixtures for the rules engine. Both the Dart projection engine and any
server-side validation must pass every fixture, always. Format:

- `setup`: game state before the play (outs, count, runner map base→runnerId)
- `events`: ordered payloads (envelope omitted; the fixture runner wraps them with ids `e1..eN`)
- `expect`: projection assertions after folding. `officialErrors` per §13.2 derivation;
  `misplays` per the development projection; `boxScore` fragments where relevant.

Adding a play GameChanger can't record? It goes here first, then the engine is fixed until it passes.
