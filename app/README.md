# Diamond app (Flutter)

Created by ticket DIA-001 (`flutter create` is run locally, not committed pre-generated).
Target layout after DIA-001:

```
app/lib/src/
  events/           envelope + generated types + event store (Drift)
  rules/            projection engine: GameState fold, official-scoring derivation (§13)
  projections/      stats, heat map aggregation (M2+)
  ui/               zone canvas, call screen, field canvas, play chain strip
test/
  fixtures_test.dart   runs ../../fixtures/plays/*.json against the rules engine
```
State management: Riverpod. Lints: very_good_analysis. Custom drawing: CustomPaint.
