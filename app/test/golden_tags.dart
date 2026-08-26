/// Goldens whose pixels differ between macOS and Linux.
///
/// Almost none do: 27 of the suite's 29 images are byte-identical across
/// platforms. These two are not, because they are dense curve work — the
/// fence spline, the base arcs, the dashed ball route — and Skia
/// anti-aliases curves slightly differently per platform. The gap is 0.35%
/// on the field canvas and 5px on the chain strip.
///
/// They are generated on Linux (`tools/goldens.sh`) because that is where CI
/// compares them, and skipped locally so a bare `flutter test` stays a clean
/// signal. CI runs them with `--run-skipped`.
///
/// A tolerance was the obvious alternative and is the wrong trade: it would
/// have to exceed 0.35% to pass, which is wide enough to hide a moved chip,
/// and it would degrade the 27 exact comparisons to accommodate two.
const platformSensitiveGolden = ['golden', 'platform-sensitive'];
