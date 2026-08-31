# Diamond — Spec Change History

Full version history for `docs/spec.md`. The spec's own status line carries the three most recent
entries; everything else lives here. Newest first.

## v0.54

**Undo hands back the scorer's entry, and stops at the plate appearance.**

Two halves of one button, and the second came out of questioning the first. Mark: *"if we record a
pitch, say a ball, and then click undo, we're undoing the location and the call as well. This is
wrong."* The call, the location and the outcome commit as one `PitchThrown`, so voiding it is right
for the stream and wrong for the scorer — mistap "Ball" for "Called strike" and you re-enter the
wristband code and the zone to fix a wrong button. Undo now repopulates the loop from the voided
payload and lands on the **location** step, with the zone and the dot still on the canvas. It does
not reopen the outcome sheet, which was the first design: the sheet is modal and its scrim covers
the count HUD, so an undo that reopened it made the *next* undo untappable.

Everything the loop appended automatically stays voided — a walk's forced chain, the strikeout's
`RunnerOut`. Nothing the scorer typed is automatic and nothing automatic survives, so the line falls
in the same place from either side. The **call draft** is deliberately not restored: the wristband
code is not on the event, only the type and the zone, so rebuilding it would roll a different code
and show the coach a number that was never on the band.

Then the depth. Mark, on the same button: *"when you call a pitch and hit the checkmark, that's a
real thing that happened that you wouldn't think would need to be undone ever."* That is the tell —
`PitchThrown` bundles a fact about the world with an entry that can be mistapped, and unlimited
undo lets one button rewind the first to fix the second, arbitrarily far back. So a plate appearance
**seals when the next one begins, and stays sealed**, and undo reaches anything unsealed.

"Begins" is *calling the next pitch* — the first type tap — or, when the call is skipped, any action
belonging to that pitch. Not a new signal: the "record last pitch" offer already dies on exactly it.

**Staying sealed is the load-bearing half.** The first version of the rule put the floor at "the
start of the plate appearance containing the most recent action," which bounds nothing — peel one
empty and the most recent action moves into the previous plate appearance, taking the floor with it,
all the way to the first pitch of the game. The wall has to be a frozen point rather than a
recomputed one.

Unlimited depth was the original promise (§6, §11.3) and it was the wrong one. Every hazard in
editing history — a count that shifts under later pitches, a plate appearance that ended earlier
than recorded, pitches belonging to a different batter — requires undo to cross a plate-appearance
boundary, and nothing requires it to. Reaching further back is an explicit edit, deliberately a
different gesture. The button **disables** when everything is sealed, rather than declining in
silence.

One consequence worth recording: the seal is session state and cannot be otherwise. The call lives
in the draft and nothing is written until the outcome commits, so "she started calling the next
pitch" leaves no trace to project from. A relaunch starts with no seal — undo still cannot cross a
`batterId` change, so the exposure is one plate appearance, not the game.

## v0.53

**§11.1's "record last pitch" backfill covers the uncaught third strike, and its canvas gains the
bounce hinge.**

The offer has existed since v0.39 and was armed only when the outcome was `in_play`. That was
narrower than the reason the offer exists. The bullet's own justification is that *on contact the
scorer's attention leaves the zone* — and a dropped third strike is that same fact: the batter is
running, the eye follows her and the ball, and the plate is the last thing anyone is looking at. The
implementation had encoded the example rather than the principle.

It stops there deliberately. Arming the offer for **every** unlocated pitch is what the principle
would permit read literally — a pitch missing its location can be given one at any time — but a
scorer who skips location routinely would then meet the affordance on nearly every call screen, and
a standing offer that is always standing is chrome. In-play and the D3K share a specific
justification that a take does not.

The **bounce hinge** comes with it. The backfill canvas had deliberately omitted it, on the ground
that only in-play pitches armed the offer and a hit ball is not a bounced one. That reasoning does
not survive the extension: the ordinary uncaught third strike *is* a ball in the dirt, so an offer
that could only record a frontal location would miss the case that motivates it. Backfill is now the
same canvas as live entry — same gesture, same two planes — and only what the release writes
differs, a §6 correction rather than a new event. §4.1's mutual exclusion holds by construction,
since the offer arms only when both location fields are null.

## v0.52

**`batterAction` gets a writer and narrows to three values (§4.1, §11.1), and the outcome sheet gains
the getaway consequence.**

The field had been defined since §4.1 was written and **nothing wrote it**. Building the writer forced
the question of what the five values were for, and two of them were recording a fact the stream already
held: `showed_bunt`/`pulled_bunt` and `slap`/`fake_slap` each carried *what she intended* alongside
*whether she offered*, and the second derives from the outcome — squared with `ball`/`called_strike`
means she did not offer, `foul_bunt`/`in_play` means she did. Storing it stored a derived fact that
could contradict its own source (§13).

So: `bunt` | `slap` | `slash`. `slash` stays explicit even though bunt posture plus a non-bunt
trajectory nearly implies it, because that inference only works when she makes contact, and the
deception is the whole scouting point. `slap` is fastpitch and should be `RuleSet`-gated; it ships
offered in both sports because `RuleSet` does not exist yet (DIA-017), which is recorded at the call
site rather than left to be noticed.

**The one-tap getaway.** Marking a wild pitch or passed ball with runners aboard offers *all runners up
one*, because that is the whole play the overwhelming majority of the time and it should not cost a trip
to the field. It is **one tap, not zero**: §11.3's rule is automatic where the rules leave no doubt and
a prompt where they don't, and a runner on third often holds on a ball that only trickled away. The
correction is action-scoped undo rather than a confirmation dialog, since confirming every common case
costs more taps across a game than undoing the rare wrong one.

Offered only with somebody aboard — rule 9.13 charges a getaway on its *consequence*, so with the bases
empty there is nothing to charge and no chip to mis-tap. A passed ball writes §13.2's pair, reusing the
D3K resolution's shape rather than a second one. And going to the field instead seeds the ball
**loose**: a wild pitch's physics is the absence of a touch, so seeding the catcher would assert
something that did not happen and the scorer would have to un-say it.

## v0.51

**§11.1's outcome sheet ranks by frequency, and the location suggestion is deleted (§11.1, §4.1).**

The sheet had ranked by Diamond's suggestion, and the suggestion could not do the job. `suggestOutcome`
returned only `ball` or `called_strike` — location knows nothing about whether the batter swung — so
its most confident case was its worst one: a pitch *in* the zone is more often swung at than taken, and
it promoted `called_strike` there. It was promoting the wrong button and calling it help.

Five primaries at fixed positions, in frequency order: **Ball · Called strike · Swinging · Foul · In
play**, with `dropped_third_strike` as a sixth when the rules let her run — an outcome that opens a
surface, like In play, not a note on a strikeout. Everything else is a wrapped chip row under an
"everything else" rule rather than a judgment about each one. Nothing consults the pitch's location, so
the sheet looks identical whatever was captured, which is what makes the positions learnable.

**Two outcomes join it.** `ball_intentional`, because four intentional balls is a different story from
four missed spots for the pitcher's line and for scouting, and it had no writer anywhere. And
`strike_unspecified`, which is not a near-duplicate of `unknown` but its opposite where it counts:
`unknown` advances nothing and turns the HUD amber (§12.5), while `strike_unspecified` says *a strike
happened and I missed which kind* and the count stays exact. Without it a scorer must either invent a
fact or discard one she had.

**`no_pitch` is removed.** Nothing ever wrote it, so no recorded stream can contain it — unlike
`swinging_strike_blocked`, whose removal made existing streams unparseable. It existed only as three
*exclusions*: a no-op in the count effect, a guard keeping it out of the pitcher's total, and a guard
keeping it out of strikeouts. Deleting it makes "every recorded pitch counts" unconditional. A balk
needs its own home on the runner surface and is ruleset-gated (DIA-017); a step-off or a granted
timeout is not something a scorer records.

## v0.50

**`RunnerAdvance` gains `cause`, and `ballInPlayEventId` becomes `anchorEventId` (§13.2, §4.2, §4.3).**

`reason` had been answering two questions at once: *why was this runner entitled to move* and *what
happened to the ball*. On a runner's advance they are one fact — `wild_pitch` says both, which is why
nobody noticed they were different questions. On a batter reaching an uncaught third strike they come
apart. Her entitlement is `dropped_third_strike` and has to stay so: it is what makes her line a
strikeout *and* a reach rather than a hit, and relabelling it sends the derivation into the hit logic
and scores a single. Meanwhile the ball's story is separately a wild pitch, a passed ball, or neither.

So `cause` (`wild_pitch` | `passed_ball`) carries the second, and the projection reads `cause` when
present and `reason` when the reason *is* the getaway. Mark, deciding the shape: *"D3K should be the
reason and WP/PB/Error/Nothing are a secondary cause."*

**Absent `cause` is an answer, not silence** — she reached on an **error**, or she **beat the throw**.
v0.49 had removed the WP/PB inference everywhere the stream could express the answer, and this was the
one place it could not: the engine read that absence as a wild pitch, charging the pitcher for a
batter's speed. It was the last inference in the path.

**Error stays on the link rather than joining the enum.** It is already recorded twice — as
`enabledByTouchId` and as the charged error — and a third home could disagree with both, which is the
same duplication §15.1's `retrieved` had just been cured of.

**`ballInPlayEventId` → `anchorEventId`.** Since §15.6 a between-pitch entry anchors its touches to the
**pitch** that already exists, so the field holds either a `BallInPlay` id or a `PitchThrown` id and the
old name asserted a type it no longer carried. Not cosmetic: the passed-ball error exemption had been
written as "`missed_catch` anchored to a pitch" and silently un-charged errors on every between-pitch
play, because nobody reading `ballInPlayEventId` expected a pitch id in it.

## v0.49

**Wild pitch vs. passed ball is the scorer's call, always (§13.2)** — the one place §13 does not
derive. The scorer says which it was on the advance's `wild_pitch` / `passed_ball` reason (§4.3), the
projection reads that, and Diamond has no logic for choosing between them.

v0.41 had made it a derivation: a passed ball was an ordinary-effort `missed_catch` touch recorded
against the pitch, a wild pitch was the absence of one. The implementation followed faithfully and
documented itself as taking the answer "from physics, never from the advance's label" — so a
`passed_ball`-labelled advance with no such touch was scored a **wild pitch**, overruling the scorer
who had just said otherwise.

**What makes this exception principled rather than convenient** is that the evidence is *optional to
enter*. Everywhere else in §13 the physical record is complete by construction — a fielder either
touched the ball or she did not, and both are recorded by the act of entering the play. Here,
`bounceLocation` is an extra tap and a `missed_catch` touch on a pitch nobody fielded is another, and
a scorer working at game speed may enter neither. Reading that absence as meaning charges the
**pitcher** whenever the scorer was busy, which is a ruling about the scorer's workload rather than
about the play. Mark, deciding it: *"we may not even have the physics a decent amount of the time
there."*

It is also not the kind of judgment §13 exists to remove. Charging an error applies an objective test
(ordinary effort) to something observable. Which of two players let the ball get away is a genuine
real-time call — a low-and-away pitch that handcuffs a catcher is exactly the case — and the only
reliable observer is the person watching. So the scorer declaring it **is** recording an observation
rather than issuing a ruling, which is what §13's principle asks for, not an exemption from it.

`bounceLocation` and any `missed_catch` touch are still recorded when entered and still feed the
pitching book, the heat maps and the error model. They become **corroboration, never the decider**:
nothing reconciles the label against them, and a disagreement between the two is not an error
condition. A passed ball still feeds §13.3's earned-run reconstruction; it simply arrives from the
label instead of from a touch.

No schema change — `wild_pitch` and `passed_ball` already exist as `RunnerAdvanceReason` values, and
the entry paths already write them. The work is deletion: DIA-015 Part 4.

## v0.48

**§23 gains a type section (§23.5); Review moves to §23.6.** Diamond had two typefaces and no written
rule for choosing between them — the rule lived in a Dart doc comment, which is not a place a design
decision survives.

**Space Grotesk carries prose, JetBrains Mono carries codes.** A code is read as a token rather than
as language: looked up, compared, or read one character at a time. The count, a wristband code
(§10.2), a fielding position, a distance in feet, a jersey number, the inning tag. Everything else is
prose, **including prose that contains a number** — "2 outs" is a sentence and stays in the prose
face; the `2` standing alone in the count HUD is not. That boundary is the whole rule, and it is drawn
at *how the string is read*, not at whether it contains digits.

The justification is movement, not decoration. A count ticking 1–1 → 2–1 in a proportional face
reflows its own row, and the eye tracks the reflow instead of the value — the same failure §23.1.1
already names when it asks for tabular numerals, generalized from digits to the whole class of strings
that are not sentences. Small letter-spaced uppercase labels (eyebrows, section tags, chip glyphs,
COUNT UNSURE) take the mono face on the same grounds: they are read as tags.

**Type is tier 1 (§23.3)** — it moves with neither the team accent nor the brightness. One scale,
rendered by both themes. The open question recorded rather than decided: light text on a dark ground
reads optically bolder, and some systems drop a weight step in dark to compensate. Diamond does not,
because the design panels do not. A full dark screen is where that becomes visible, not a swatch, so
if it changes it changes here.

**The faces ship in the bundle, never fetched**, which is §12.6/§19.1/§21.5 applied to a resource that
does not look like data. A font pulled from a CDN — including the `google_fonts` package's default
behavior — is a blank label in a dugout with no signal, failing on exactly the day it matters.

**Weights are 400/500/700, and that set is a constraint rather than an inventory.** This is the part
worth writing down: an unbundled weight does not fail. Flutter renders the nearest bundled weight, so
asking for a w600 that was never shipped produces something that looks deliberate and is not. One such
call site existed when the section was written.

The scale itself stays out of the spec, the way §23.2 names three colors without enumerating every
surface step: it is a token set in `app/lib/src/ui/theme/brand_type.dart`, read out of the design
panels rather than invented. Its shape — display and headline for what is read across a dugout, title
and body sharing three sizes separated by **weight and leading rather than size**, labels for text
inside components — is described in §23.5 without pixel values, which are the kind of thing §23's
preamble keeps out of prose.

## v0.47

**The semantic reservations get real colors, and stop sharing (§23.2).** DIA-012's palette was
placeholder by its own admission; 1A "Infield" replaces it, and the three reserved states become
**Dusk** (violet, uncertainty), **Rosin** (amber, misplay) and **Ejection** (magenta-red, the app
failing).

Uncertainty and misplay were both amber on the reasoning that both mean "this needs your judgment
later." They do not ask the coach for the same thing: one says *I do not know what happened*, the
other says *I know, and someone muffed it.*

**Size governs the treatment**, which is why amber survives in one place and not the other. Chroma is
what separates a reserved color from Clay, but large areas of high chroma are unreadable after two
innings — so the persistent count HUD takes a tinted field with a saturated label, and the 40px chip
takes a full fill. Rosin's separation from Clay is lightness plus saturation rather than hue. Dusk is
violet because nothing on a ball field is, so it cannot be misread as grass, dirt or blood.

Two rules that follow: **Rosin is a fill, never text or line** (amber type on Chalk is illegible
outdoors), and **Ejection is the app failing, never a fielding error** — two phrases that mean
opposite things here.

**`callable` stops being a reservation.** The three above are events; callable is a standing
description of where the tool works, true of most zones most of the time, and a hue of its own would
put permanent alert weight across half the grid. It becomes Grass in three steps — wash = callable,
solid = called, dashed = off — with the wash carrying a border, since a 14% fill alone reads as a
smudge. General rule: **a reserved color is for an event, not a state.**

**A third color tier appears**, described in §23.3's terms but governed by neither: a **categorical
scale** (pitch types), whose rule is that its members stay mutually distinguishable rather than that
they express identity.

## v0.46

**D3K arming is the scorer's, not the pitch's (§11.3), and `swinging_strike_blocked` is gone (§4.1,
schema change).** v0.41 armed the resolution on a bounced pitch or a catcher-misplay touch. Both
halves were wrong: a passed ball on a letter-high fastball lets the batter run exactly as a ball in
the dirt does, and the misplay that would prove it is entered *after* the moment arming has to
happen. So the offer stands on **every third strike she was entitled to run on** — first base open,
or two already out — and is **hidden**, not greyed, where the rules prevent her running, that being
the one case with no judgment in it.

`swinging_strike_blocked` goes with it. "Blocked" is not a property of the pitch the scorer is
judging but of what the catcher did, and the app already holds it twice: `bounceLocation` says the
ball was in the dirt, §13.2's derivation says whether anything got away. Removing it also removes the
split in the swinging-strike vocabulary.

**It is declared with the pitch, not corrected after it.** A dropped third strike is the equivalent of
a ball put in play — an outcome that opens a surface, not a note on a strikeout — so it belongs on
§11.1's outcome sheet beside **In play**, where a scorer will look for it, rather than in a prompt
that appears after every eligible strikeout. Choosing it asks which strike it was, then what happened
to her. The automatic strikeout out is never written, so nothing is voided and no phantom out reaches
the stream. Labeled **Dropped 3rd strike**: less precise than "uncaught" and the word scorers use,
and already the wire word (§4.3).

Four one-tap endings plus the field. **Out at first** writes 2-3 with a real putout and assist —
credit the bare recorded strikeout never carried, and the reason even the ordinary D3K needed fixing.
**Field…** opens §15.6's surface with the batter walked up, since a D3K is a pitch-anchored draft
(v0.45) with a runner entitled to first: play #5 is entered with the ordinary play grammar and
nothing D3K-specific.

## v0.45

**Between-pitch entries are play drafts with a different anchor (§15.6).** v0.42 specified them as
"a single fact, not an accumulating chain" — one event, committed by the reason chip, with no chain
strip and no ✓. Building it that way produced a parallel mechanism no existing editor understood: a
caught stealing where a missed tag makes the runner safe was **unenterable**, because the chain strip
is what retypes a touch and links an advance to it.

They are the same structure. A play hangs its chain off the `BallInPlay` it mints; a between-pitch
entry hangs it off the pitch that already exists. So the chain strip, every §15.3 chip, and §15.5's ✓
apply unchanged, and official scoring reads one shape rather than two. The catcher holds the ball by
seed; tapping her says the pitch got past her, and the next fielder is then making a play on a loose
ball rather than receiving a throw (§15.1's rule, carried over).

The SAFE and OUT vocabularies stay disjoint by state — nothing is stolen on a batted ball, nothing
comes "on the hit" when there was no hit — with "on an error" in both, since that is how a runner is
safe on a missed tag.

**Cost, deliberately paid:** a plain steal is four gestures rather than three (open · drag · chip · ✓).
With a chain to edit, committing on the first chip is premature. DIA-008's accept criterion moves with
it.

## v0.44

**One spelling for failing to receive a pitch (§13.2, §11.3, §15.6).** Receiving a pitch is binary.
Whether the catcher got a glove on it or it went straight past her changes nothing that is scored,
and asking the scorer to say which is a judgment with no consequence — the question at entry is
"passed ball?", yes or no. So the passed-ball touch has exactly one spelling, **`missed_catch`**,
chosen over `dropped` because it claims less: `dropped` asserts she had it and lost it. §13.2's
definition, §11.3's D3K Safe-passed-ball fast path, and §15.6's PB chip all now name it.

This does not widen the exemption. Two misplays that anchor to a pitch stay chargeable: `wild_throw`,
because a throw is a thrown ball (§14 play #5's E2 stands), and `tag_missed`, because muffing a tag on
the batter-runner is a play on her rather than a failure to receive. `missed_catch` remains legal on
batted balls; it simply has no producer there, since §15.1's "Missed it" records no touch at all.

**Implemented in DIA-008d**, which is the first writer of the value.

## v0.43

**§15.1's entry grammar rewritten from DIA-008 field testing (design review with Mark).** Four
changes, one principle: the surface should mirror how a scorer actually watches a play.

**Trajectory first.** The batted-ball type (`ground`/`line`/`fly`/`popup`/`bunt`) is the first
required tap and gates the canvas, because it drives every later option — the what-happened
popup's contents, caught-vs-fielded readings, the fly-out inference. The old order (landing tap,
then trajectory) had the scorer commit a coordinate before the surface knew what kind of ball it
was describing.

**The ball's path, drawn or implied.** Drawn: two taps — first bounce, then where it ended up —
rendered as an accent streak with live distances; the second tap is simply omitted for routine
balls. Implied: **drag the fielder to where she made the play** — wherever she is dropped is where
the ball went. Her release point becomes the assumed `landing` and the touch's own `location`
(§4.2's field, carried since v0.1, finally earning its keep), and a trajectory-driven popup
disambiguates: air — caught / dropped / missed it / picked it up; ground — fielded / booted /
missed it. "Missed it" deliberately records **no touch**: a ball she never touched is officially
nothing (§13), but the play still knows where the ball went and that she got there. Her moved
position is render-only — per-play repositioning is where she made *this* play, not §16.4
alignment data.

**Safe/Out at the approached base.** Runner drags resolve on a Safe/Out pair that appears at the
base the runner nears — the GameChanger interaction, kept because it was right — replacing the
always-offset out affordance. The pair stacks vertically (SAFE on top, OUT beneath) rather than
sitting side by side under one thumb, out in foul ground beside first and third and straddling
the bag at second and home; the pills' own positions count toward "engaged with this base," so
reaching for one can never take the runner out of range of the base it belongs to. The pill
under the runner lights up as she is dragged onto it, and resolution is nearest-wins — the
midline between the two is the boundary — so what glows is what commits. The base itself reads as safe; `how` inference (force/tag/fly-out)
is unchanged and confirmable on the chain node.

**⚖ moves to the baserunning surface.** Obstruction and runner interference are baserunning
facts, so they leave the standing strip button and live on the runner-consequence chips' menus:
selecting one inserts the ⚖ into the chain just before that consequence and links it (an advance
re-attributes to the call; an out's `how` becomes `interference`).

**SAFE and OUT get classified popups with disjoint vocabularies.** Releasing a runner on a
SAFE/OUT target opens a centered popup naming what happened, and the two lists never overlap
by rule — a runner can only be safe on obstruction and only out on interference. SAFE: the hit
itself (Single/Double/Triple/Home run for the batter, "On the hit" for runners — the only answer
that raises hit rank) / on the throw (linked to the latest touch) / on an error (linked to the
latest misplay) / fielder's choice / obstruction (⚖ inserted and linked). OUT: force/tag/fly-out
offering only the outs physically possible there, likeliest first: a force needs the very next
base *and* the chain of occupied bases behind her, a catch removes every force, fly out is the
batter's alone and the appeal a runner's alone — plus interference (⚖ + `how: interference`). Automatic
movement — the walk-up, cascade pushes — never asks. This forced a derivation fix the popup's
distinction exposed: hit rank now counts only unenabled batted-ball legs, so "took second on the
throw" is a single plus an advance, never a double.

**Catcher's interference becomes an outcome variant — E2 by rule (§4.1 schema change).** It
belongs on the outcome surface with Ball/Strike/HBP/In play, and it is structurally identical to
`hit_by_pitch`: dead ball, no count effect, PA over, batter awarded first with the forced chain.
The loop emits `RuleCall{interference_catcher, againstPosition: 2}` ahead of the award, and
official scoring charges **E2** (kind `interference`) — the one error with no misplay touch
behind it. §4.1's "follow-up events, not more outcome variants" note is narrowed accordingly;
fixture play-07 covers the play. (`RuleCall` also joins the undo-unit walk — previously a ⚖
inside a committed play broke action-scoped undo.)

**The batter runs on contact.** The surface opens with the batter-runner already walked up to
first, forced cascade applied — a ball in play means she's running, so the common case (she's
safe) costs zero gestures. The presumption resolves mechanically, never lingers: a caught first
touch voids the unattributed walk-up and records the fly out (putout to the catch); an out marked
at the base a runner's last leg reached absorbs that leg into the out, so no phantom
`RunnerAdvance` ever commits alongside a force-out; and a misplay first touch claims the batter's
provisional reach — §13.2's hit-vs-error flag lives on the first touch, so `reached_on_error`
derives with zero extra taps. Presumed movement renders **in motion**, a third of the way up
the line rather than parked on the next base, so "she's going there" never reads as "she got
there"; a caught ball returns everyone to their bases, and the OUT dialog then offers
**Didn't tag up** (§4.3's `appeal`) for the runner doubled off. Outs are capped where they are
authored: at three the surface drops the OUT pill entirely (§4.4's `halfEnded`, which the fold
has always computed and nothing consumed), so no fourth out can be entered — and the appeal
disappears with two away for free, because the catch was already the third out. The *inning
flip* itself — emitting `InningHalfEnd`, starting the next half — remains DIA-009's. Fielders drag live (she rides the finger), and every popup on the
surface — the trajectory question included — is a centered modal sized to its content.
Throws are one tap: while the ball is held, tapping another fielder sends it to her —
held-vs-loose is derived from the last touch type, so a dropped or booted ball can't be
"thrown," only played — and the ball's route draws as dashed segments, touch to touch. A
throw arriving at a base with a runner provisionally heading there pops the SAFE/OUT pair at
that bag — the 6-3 is five gestures with no runner dragging at all — while runner taps alone
never raise the pair; resolution targets need a real drag or a throw that puts the question.

**§13.2's misplay set and `ordinaryEffort` defaults, settled on one principle.** *If it is worth
putting in the play-by-play, it has to be an error; otherwise it is not worth mentioning.* So
`tag_missed` joins the misplay set as a charged **fielding** error and the printed default list
at `true`: recording a missed tag is itself the claim that she should have made the play.
`wild_throw` deliberately stays a judgment call — a throw can sail and cost nothing, leaving the
runner exactly where a good throw would have. A runner who beats the tag on a great slide is not a missed tag —
she is safe, and nothing is recorded at all. `deflected` stays out of the set entirely (the ball
that hit her with no play to be made is a physical fact, never fault), and `bobbled` stays
unresolved-by-default, since that one really is a judgment call. Both the misplay set and the
effort defaults now have exactly one definition, in the rules layer, which the play draft reads
at commit — they had drifted into two disagreeing copies.

**§11.1's outcome surface gets two anchors instead of one.** The suggestion keeps the lead
button; **`in_play` now carries the same weight in a row of its own at the bottom, always** —
never suggested, since contact isn't inferable from a location, but it is the other outcome that
changes everything, and a surface where the highest-consequence choice moves around is a surface
that gets mistapped.

**§15.4.2's first-base prompt is withdrawn.** "The throw arrived and she is safe" reads as a
contradiction only if you know the throw beat her — and Diamond has no timing model, so it cannot
tell a dropped throw from a bang-bang infield single. Worse, the prompt was firing against the
batter-runner's *presumed* walk-up (§15.1's runs-on-contact), asking about an answer the scorer
had never given. The prompt mechanism stays for cases where the record is genuinely incomplete
(the spec's "chain ends at a fielder with no out and no attribution → bobble?"); the drop itself
remains one tap on the node that took the throw. Relatedly, answering **SAFE** on a force play
now re-authors the walk-up leg as a real answer, so the runner stops rendering in motion and
stands on the bag — nothing is presumed once the scorer has spoken, and releasing her on the
base she already occupies settles her rather than minting a `from == to` leg (§4.3 reserves
that shape for surviving a rundown). The what-happened popup likewise follows the ball rather
than the trajectory: catching is offered only while the ball is still in the air, which it is
until somebody touches it — except for a deflection, the one touch that leaves it up, so a
liner off the pitcher's glove can still be caught by the shortstop. Deflection is a line-drive
and grounder option only. A catch retires the batter wherever it happened, while
`landingIsCaught` keeps answering the narrower question §4.2 asks it.

**The SAFE menu offers only what could have moved her.** Field testing a runner tagging home on
a caught fly turned up a menu of impossibilities: "on the hit" when nothing was hit anywhere she
could run on, "fielder's choice" when the batter was already out in the air, "on the throw" when
nobody had thrown, and obstruction — a call rare enough that offering it on every play is noise.
The set is now context-gated: **"Tagged up"** replaces "on the hit" once the ball has been caught,
fielder's choice disappears with it, "on the throw" requires evidence that a throw happened (a
reception or a throw that got away, not merely a touch), and **when exactly one answer remains the
surface does not ask at all**. Both ⚖ calls left the first-pass SAFE and OUT menus for the chain
nodes, where they are found when looked for.

**§13.6: sacrifices, one derived and one judged.** A sacrifice fly is fully visible in the stream
— any ball caught in the air, fewer than two outs, batter retired, a runner in from third on the
ball, no charged error — so it derives and the scorer enters nothing. A sacrifice bunt is not: nothing
physical separates bunting to move the runner from bunting for a hit, so it becomes §13's second
judgment flag after `ordinaryEffort`, stored as `BallInPlay.sacrifice` (schema change) and offered
by the field surface exactly when the question is live — a bunt that moved a runner up. An
explicit flag overrides the derivation either way. Both are plate appearances, neither is an
at-bat, which is what `BatterOutcome.atBat` was added for.

**A stream audit closes three derivation holes (§13.2).** Reviewing everything that touches the
event stream turned up three ways a play could be scored wrong. **Obstruction on the batter-runner**
derived as a *single*, because `obstruction` was missing from the non-batted reach reasons; it is
now not a hit, not an at-bat, and charges a fielding error to the fielder who obstructed —
which required the ⚖ to name her, so the surface asks. **A reach claiming an error with nothing
to link** also derived as a single: the SAFE popup would offer "On an error" with no misplay on
the chain, producing an advance whose cause was unrecordable. The popup now offers that answer
only when there is a misplay to point at, and derivation treats an unlinked `error` reach as
`reached_on_error` regardless. **The ⚖ link was dropped at commit** — `enabledByCallId` existed in
the schema on both `RunnerAdvance` and `RunnerOut` and had zero writers, so every obstruction and
interference call committed a consequence whose cause could not be recovered from the stream. Both
are now written. `BatterOutcome` gains **`atBat`**, since "not an at-bat" needed somewhere to live.

The audit also confirmed what is healthy: every payload in a real recorded game validates against
its JSON schema, putout and assist credit follows the touch chain correctly, and the action-scoped
undo unit walks correctly across all four shapes now in play.

**§16.3's beyond-the-fence prompt ships, as two plain Yes/No questions.** Where the ball ends
up decides which one gets asked: a fair landing past the fence asks **"Home run?"**, while a
ball that landed in the park and *ended up* past the fence asks **"Ground rule double?"** —
the bounced-over ball, the only shape that award actually has. Yes awards four bases apiece
(every run an RBI) or two apiece respectively, replacing the draft's runner movement wholesale,
superseding the opening walk-up so nothing stays provisional, and clearing `offWall`. **No
proceeds as an ordinary play.** The RBI rule gains `ground_rule` alongside `batted_ball` — a
ground-rule double that scores a runner drove her in — and the canvas's render margin past the
fence widens so that band is a real tap target.

## v0.42

**§15.6: the idle field — between-pitch runner events (DIA-008d).** Field testing of the DIA-008
design surfaced a gap: the field canvas existed only while a ball was in play, so there was no way
to look at the field between pitches — and no entry surface at all for steals, caught stealings,
pickoffs, or runners advancing on a wild pitch or passed ball, even though §4.3 has carried the
event vocabulary since v0.1. A field affordance on the loop's idle surfaces now opens the same
canvas with no ball in play: defense and runners visible (alignment drag remains §16.4, M2), and
runner drags enter between-pitch events via a reason chip row — advances `stolen_base` (default) /
`wild_pitch` / `passed_ball` / `defensive_indifference`, outs `caught_stealing` (default) /
`picked_off`. The chip tap commits immediately, with no ✓ and no journal: each entry is a single
fact, not an accumulating chain, so §15.5's commit machinery deliberately does not apply.

Two rules keep it consistent with the rest of the spec. The `passed_ball` chip emits §13.2's
physics pair — `FielderTouch{2, dropped, ordinaryEffort: true}` anchored to the most recent pitch,
advance linked via `enabledByTouchId`, and later runners advancing in the same window reuse the
touch (one PB, one touch, N advances) — while `wild_pitch` is the advance alone, exactly the D3K
Safe pair's logic. And each entry is one action-scoped undo unit (§11.3) that never rides along
with the preceding pitch's unit — which forces the undo-root mechanism to stop keying on event
type alone, since a `RunnerAdvance` is a consequence after a walk but a root when the scorer
authored it directly. A steal noticed late stays a §6 insert with `effectiveAfter`; the idle field
is for the ones seen live.

## v0.41

**Walk and HBP forced advances auto-apply; undo becomes action-scoped (§11.3).** The forced chain
on a ball four or HBP is rulebook arithmetic — batter to first, each runner moved only while the
chain of occupied bases behind them reaches first — with nothing in it to decide, so DIA-007b's
confirmation step is removed before it ships: it protected against an error (a mistapped outcome)
that confirmation cannot catch and undo can. The consequence that makes this safe: undo is restated
as **action-scoped** — one tap voids the last scorer-authored root event (a `PitchThrown`, a
`CountCorrection`, a committed play) together with every event the loop auto-appended for it, so a
bases-loaded walk reverses in one tap rather than five. Unlimited depth is unchanged; the unit
changed.

**D3K arming is redefined to key on the catch, not the pitch (§11.3).** An earlier draft of this
version armed on `swinging_strike_blocked` alone — conflating "in the dirt" with "uncaught." A
catcher can drop a clean third strike, called or swinging, and that fact lives on the catch (a
`FielderTouch{2, dropped}`, §13.2), never on the pitch. Since the misplay-touch entry surface is
§15's play chain, the whole resolution flow moves to DIA-008: play #5 enterable end-to-end, plus
one-tap fast paths for the plays that end at first — Out (tag), Out (throw), Safe (wild pitch),
Safe (passed ball) — encoded per play #5's conventions (the batter's advance always carries
`dropped_third_strike`; a D3K touch anchors to the pitch event; the Safe pair is §13.2 physics,
never a ruling). Until DIA-008 lands, the loop records the strike-three out unconditionally and a
real D3K reverses with one action-scoped undo. Kept on the roadmap prominently because this is
among GameChanger's most fumbled plays.

**§13.2 gains the WP/PB derivation rule the ER reconstruction was already assuming.** A passed
ball is an ordinary-effort catcher misplay touch (`dropped`/`missed_catch`, `ordinaryEffort: true`)
recorded against an uncaught pitch; a wild pitch is an uncaught pitch with no such touch. Derived
from physics at projection time, never stored as a ruling — the same pattern as every other §13
judgment, and the missing definition behind §13.3's "as if errors and passed balls hadn't happened."

**§4.1 adds `strike_unspecified` (schema change), and §11.2's bailout row becomes BALL / STRIKE /
FOUL / IN-PLAY.** Bailout's word for "the count advanced and I don't know how": a strike of unknown
kind — called, swinging, or possibly an uncaught foul — with full count effect (strike three at two
strikes) and exclusion from swing/contact analytics. Below two strikes a missed foul tapped as
STRIKE is harmless (identical count effect); at two strikes FOUL vs STRIKE is a read of whether the
at-bat ended — which the field shows — not a judgment about the pitch, so the outs invariant never
rides on an ambiguity. Chosen over recording `called_strike` by convention (fabricates a no-swing)
and over a three-button row with uncertainty machinery at two strikes (drags amber into exactly the
moment bailout exists to keep simple).

## v0.40

**The pitch-happened checkmark (§10.3), and an honest tap budget (§11.1).** The loop's transition
from calling to recording needs an observable act — the pitch *happening* is not something Diamond
can observe, and nothing else on the surface can tell "the pitch is in the air" from "the coach is
still deciding." DIA-007a first built that act as a free-standing "Pitch thrown" button below the
canvas, which read as page chrome; v0.40 replaces it with a checkmark sitting beside the code — with
the artifact it confirms — which doubles as "this call was the one used." For a verbal-calling team
(§10.2), which has a pending call but no code, the checkmark stands alone in the code's slot. It
appears only once a pending call exists: a half-made call has nothing to confirm, so the coach
finishes it, replaces it, or takes §11.2's skip — which also retires the transitional type-without-zone
intent capture DIA-007a briefly allowed. §11.1's full-mode tap budget is restated as **5** (type,
zone → code; ✓; actual location; outcome confirm) — the confirm tap was never in the old count of 4,
which predated any statement of how the loop learns the pitch happened.

## v0.39

**Split duty is the design center at full capture depth.** Calling pitches is a full-attention job:
read the count and the batter, choose, yell the code, watch the glove. So is scoring a 9-3-2-5-1
double play. One person cannot do both at full capture depth, and the spec stops pretending
otherwise: the canonical full-capture arrangement is **caller + scorer** on two devices (§12.2),
with combined single-operator play kept as the supported compromise — a scorer with `pitchCalling`
off, or a caller-scorer with `battedBallDetail` off riding §11.2's ladder. §10.3 states whose
screen the calling UI is; §11.2 notes the ladder and the split are different axes. This inverts
the framing of Open Question #1's v0.2 resolution without unresolving it: Diamond is still the
calling mechanism; what changed is which arrangement the UI optimizes for.

**The caller's bundle grows to everything read at the plate.** The seam between duties falls where
attention falls: the caller's eyes are on the glove at plate-crossing for every pitch — including
the ones the scorer physically cannot locate, because contact snapped their attention to the play.
So the caller's bundle is the call, the actual location, and the actual type when the pitcher
crossed up the sign; the scorer's bundle is everything after — outcome, batted ball, fielding,
runners. Mechanically this is a sketched `PitchObserved` annotation event (`actualLocation?`,
`bounceLocation?`, `actualType?`, same mutual exclusion as `PitchThrown`) plus a `pitchObservation`
capability, paired to `PitchThrown` by time adjacency exactly as `PitchCalled` is. The schema lands
with M2's sync work, like `PitchCalled` — nothing here changed `schema/`. Granting the capability
flips the primary's location capture off, so overlap is configuration-prevented; where it happens
anyway the primary is authoritative and the audit view shows both. §12.7 gains the sequencing
consequence: two-device sync is what makes calling usable at full capture depth — the calling
feature's completion, not an enhancement.

**Ball-in-play location: both orders, and backfill at any time (§11.1).** On contact the scorer's
attention leaves the zone, so location-first is often impossible — but an implied skip on `in_play`
would throw away the times it isn't. Both orders exist: the actual-location step stays in the loop,
and the outcome row is reachable without it — score the whole play, and the loop's return offers
"record last pitch," which the scorer takes or doesn't. The offer never expires: a missing location
can be added from the pitch summary between innings or from the game stream after the game, video
up, charting every ball in play at leisure — the event inspector (§12.3) offers it on any
`PitchThrown` missing a location. All of it is one mechanism, a §6 correction to the committed
`PitchThrown` — the same post-hoc pattern as batter-action chips — so the pitch commits promptly
with `actualLocation` null, nothing is held open, and provenance shows exactly when and by whom
each location arrived.

## v0.38

**Replaced §10.1's authored call-zone rectangles with a canonical 5×5 partition of 25 cells.** The
plate and its surround are now partitioned once — the 3×3 strike-zone grid, whose outer ring is the
zone's edges (the black), plus one off-the-plate stop beyond it on each axis, corners included. Each
axis reads *off-in, in, middle, out, off-out* laterally and *off-low, low, middle, high, off-high*
vertically.

The change came out of a question the old model couldn't answer: coaches mean different things by
"down and away" depending on the count — the black on 0-0, off the corner on 1-2. The previous default
(3×3 + 4 compass chase zones) had no diagonal, so the 1-2 version had no zone to be. 25 gives it one.
Most teams will never separate the corners; the point is that the team that wants to call *too low and
too far away* doesn't have to redraw the model to do it.

Ring cells are **unbounded in extent but nominal in target**: their `bounds` run outward without limit,
because the partition cannot have a hole and containment must resolve a pitch however far off the plate,
while their centroid is placed as though the cell had the same dimensions as an in-zone cell sitting just
beyond the edge. An unbounded region has no geometric centroid, so the target has to be nominal, and
equal dimensions is both the simplest choice and the closest to what "off the plate that way" means. The
target lands half a cell out — ≈2.8″ beyond the plate edge laterally and ≈4″ past knee and armpit
vertically at 12U. The lateral figure is tight and is recorded as a starting place to revisit against
practice, not as a derived constant.

**A team's layout is now a grouping of those cells, never an independent set.** `bounds` is derived
from the grouping rather than authored, which makes overlapping zones and uncovered gaps
unrepresentable instead of merely invalid — and containment classification (§17.4) depends on exactly
that, since freeform intent and observation mode (§19.5) both need any point to resolve to one zone. A
10U team groups a whole edge into one "chase high"; a 14U team leaves those cells separate.

**Zones are batter-relative; coordinates stay absolute.** §10.1's vocabulary was already relative
("Up-In", "Low-Away") while `ZoneCoord` is absolute in the catcher's view (§3.1), and nothing said how
one became the other. The wristband settles it: a code has to mean one thing to the pitcher reading it,
so a zone is named from the batter's point of view and mirrored to an absolute `intendedLocation` when
the pitch is written. `intendedZoneId` then aggregates across a lineup without mixing inside-to-a-lefty
with away-to-a-righty, which §17.4's command rubric depends on. Nothing mirrors on screen: the call grid is
drawn on the entry canvas itself, so the geometry stays absolute and fixed and only the *label*
resolves — "In" sits at negative x for a righty, positive for a lefty — which preserves §11.4's
never-mirror rule rather than excepting it.

**The call grid lives on the entry canvas, not beside it.** §11.4 said both: line 481 had the zone rect
carrying the grid, while the canvas-extents table and two notes below it described a side-by-side
layout competing for horizontal room. The single-surface reading wins, and v0.38 is why — the canvas
already spans x ∈ [±4.0] and y ∈ [−1.05, 1.5], which is exactly where the 16 ring cells sit (their
nominal targets are at x ≈ ±1.33), so the 3×3 lands inside the zone rect and the ring fills the canvas
around it. The coach calls and records on the same picture, and the width the side-by-side layout would
have spent on a second grid is freed for the screen's other furniture. The stale side-by-side notes are
corrected.

Grouping is also what keeps intent comparable over time. A player's history follows them (§22) across
age groups whose vocabularies differ, and because every layout groups the same 25 cells, any two roll
up to a common frame. Independently authored rectangles would not.

**The callable set is per pitch type, and entirely the coach's.** Each type carries its own subset of
the team's zones. Diamond has no opinion about which locations suit which pitch — a high drop and a low
rise are real calls — so every cell is available to every type, the default is all-callable, and
narrowing is always the coach's act rather than the app's inference. The matrix is sparse in practice,
which is what keeps a six-pitch arsenal printable (cell count is the sum over types of that type's zone
count × k, not the cross product), but nothing enforces sparsity. The call screen offers exactly what
the **active card** can express and never more: a code the coach can yell must be a code the pitcher
can look up, so editing a type's zones invalidates the card and requires a regenerate (§10.2).

**Resolves Open Question #7.** The coach picks a zone off the grid and there is no sub-zone nudge on
the call side. A nudged coordinate has no code — §10.2 keys codes to (pitch type × call zone) — so
refining intent past the zone would record a target the pitcher was never told and then grade them
against it in §17.4. Situational variation in what a zone *means* is read off `actualLocation` against
the count instead. Freeform capture remains for contexts with no call at all: solo scoring, verbal
calling, observation mode.

**§10.2 records that k is per call, not per card** — as direction, not as implemented behavior. Calls
are not thrown equally often, and a code's job is to keep the frequent ones from becoming recognizable,
so a call's code count should follow how often it is expected to be called; uniform k stays the starting
default. Card size therefore reads as the sum over calls of their code counts, and the three-digit format
caps a card at 9 x 90 = 810 cells, which the generator must enforce rather than silently emitting
four-digit codes. Allocation belongs with wristband setup, which has no ticket yet — hence recording the
direction here so it is not rediscovered.

**§11.4 states what the grid draws, and when.** The 3x3 strike zone renders at all times, on the
calling surface and the actual-location surface alike, because it is the frame every location is read
against. The sixteen cells around it are drawn only while a pitch is being called and only where that
pitch can actually be called, since they are the available choices; on the actual-location surface they
are not drawn at all and are merely implied, containment still resolving any point into exactly one of
them (§17.4). A callable zone draws as one swatch the size of a strike-zone cell, centered on its
target, never one mark per member cell — a grouped zone is one call with one code, and painting its
cells separately shows several targets where there is one.

**§10.3** now states that type precedes zone because the vocabulary depends on the type, and that the
grid's geometry is fixed and never re-flows between types — only which cells are callable changes.
Muscle memory across 120 pitches is worth more than larger targets.

Two §10.3 corrections follow from the above. The type row is **no longer color-coded**: §23.1.2 allows
one accent live at a time and it belongs to the selected type (§23.1.3), so per-type color was earlier
guidance that §23's precedence rule makes a defect rather than a competing option. Color-coding pitch
types remains plausible on a **review** surface, where it is categorical encoding in a chart rather
than a second accent and §23.4's different rules apply; it is recorded as such so it is not re-added to
the calling screen. And the **tap-and-hold chase gesture is removed**: with 25 callable cells every
off-plate location is directly tappable, a hold could only ever resolve to a cell that is already
callable, and it was undefined on the center cell, which has no outward direction.

No event-schema change: only `intendedZoneId` (a string) reaches `pitch_thrown.schema.json`;
`CallZone`'s shape is team configuration, so no codegen, fixtures, or regeneration are involved.

This version also repairs a protocol lapse: v0.37's content landed in the spec, and its full entry
landed here, but the spec's own header and status line were never updated and still read v0.36. The
status line now carries v0.38 / v0.37 / v0.36.

## v0.37

**Promoted design language to its own top-level section, §23**, and left §18.7 as a pointer stub. The
old placement was scouting-scoped in name only — DIA-005 and DIA-011 both specify a "§18.7 review pass"
for the pitch entry canvas, a §11 surface — so the section is now stated to be app-wide. Appended rather
than inserted: §23 follows §22 as this document has always grown (§22, a UI/projection section, already
sits after §21's technology decisions), which avoids renumbering §19–§22 and breaking `CLAUDE.md`'s
§21.5 non-negotiables, DIA-002's §21.5(1), and every reference to §19.5, §16.x and §22.1. The stub keeps
existing ticket acceptance criteria resolving correctly.

§23 carries a **precedence rule**: it supersedes design guidance stated earlier in the spec, and where
earlier text conflicts, the earlier text is a defect. The boundary is narrow and stated explicitly —
§23 governs design language, not derived geometry (§11.4), data-model rules (§1–§7), or a surface's own
composition. A design pass does not relitigate a computed value; if §23 appears to contradict one, §23
is wrong.

New: **§23.2 semantic reservations** (amber = uncertainty *and* misplay — one idea, "this needs judgment
later"; red = error), pulled out of the old principle 2 because they are load-bearing across §12.5, §13
and §15.3 and were too easy to miss inside a list item. New principle **7, "never color alone,"** which
§15.3's underline convention was already following without it being written down.

New: **§23.3 color contexts** — brand baseline, own-team accent, opponent accent, with one accent slot
between them, so "one accent system" is preserved rather than weakened: what is contextual is the
accent's value, not how many are live. The opponent accent is a drill-in condition rather than a game
state (a Tuesday scouting report themes as Saturday's live game does), and deliberately does not apply
to schedules or any list of several opponents, where eight accents at once destroys the signal by making
it constant. Color is stored as data and derived at read time per Core Principle #3; derivation owns
contrast in both modes since seeds are arbitrary; unset opponent colors fall back rather than being
invented.

New: **§23.4**, generalizing §11.4's per-surface fidelity split — entry surfaces are used at speed in
sunlight and spend nothing on decoration; review surfaces are used at leisure and are where the product
is judged.

Opened **Open Question #10**: team colors that collide with the reserved amber/red. Three resolutions,
all with real costs; shelved for a field test. Blocks the picker, not DIA-012's plumbing.

## v0.36

**Built the batter silhouette** as a derived, first-class part of the entry canvas (§11.4), reversing the earlier decision to keep it behind a debug flag as a calibration instrument. It is a location cue first: a coach picks a call and reads an actual against a body, not against an empty rectangle. It ships **off by default** — the geometry is right but the *drawing* is not yet convincing, so the figure is hidden pending DIA-013 and the canvas carries no occupied-side cue in the meantime. Visibility is a parameter rather than a temporary constant, since a future practice state (bullpens with no batter) wants the same switch driven by a user setting.

The objection that kept it off was real and is **answered rather than overridden**. `y ∈ [0,1]` is *this batter's* zone, so a silhouette drawn at one fixed height is honest only for a batter of that height and would visibly contradict the zone rect for a tall or short kid — on the surface a coach looks at 120 times a game. The fix is to derive her from the zone profile: her knee is `y = 0` and her armpit is `y = 1`, definitionally the zone's own edges, so she tracks the rect for every batter by construction and cannot drift from it. Stature follows from the profile (58″ at 12U via §3.1's canonical pairing) and everything else is human proportion as a fraction of stature. This is the escape clause the earlier text already anticipated — "driven from a batter-height parameter so it cannot drift from the zone it illustrates" — applied to the entry canvas rather than only to review surfaces.

**She is the only occupied-side cue.** The batter's-box fill (frontal) and shading (top-down) are dropped from both planes: two competing indicators for one fact is worse than one, and the boxes remain the reference frame for location on either side of the plate regardless of who is up. `x` stays absolute and the canvas still never mirrors — only the silhouette moves. She renders in the **frontal plane only**, since her job is the vertical knee-to-armpit read and the top-down plane has no axis for it, and she takes **no pointer events**: a pitch may be recorded anywhere on the canvas including at her body, so a silhouette that swallowed taps would make the region it occupies uncapturable. Her head is frame-cut at upper-face level by the +1.5 top, which is that trim working as designed.

Also recorded in §3.1 as planned, uncontested work: **batter height becomes settable, and the default profile is chosen by sport and age level** rather than hardcoded to 12U fastpitch. Everything derived from a profile is already expressed as a function of its two numbers so that lands without a second geometry pass.

## v0.35

Made **`BounceCoord.depth` optional** (§3.3). §11.1 had always said that skipping the second placement records "in the dirt, depth unknown", but nothing in the schema could express it: `depth` was required, `PitchThrown` has no bounced flag, and so the one honest encoding was to drop the bounce entirely and lose an observation the coach actually made. The hinge is reached by a release in the dirt band, which always yields a lateral position, so `x` stays required and `depth` alone becomes absent. **Absent is never 0** — `depth: 0` means the ball hit the plate's front edge, which is a measurement, not a gap. Both consumers that don't need depth already read fine without it: §4.1's conventional `y_ground` coordinate needs only `x`, and §17.4 needs only that a bounce happened.

Corrected §11.4's **top-down plane geometry**. The section's own constraints — same px-per-x as the frontal plane, and isotropic — leave the depth range no freedom at all: sharing px-per-x fixes px-per-inch, isotropy then makes the shared drawing rect fix how many inches fit vertically, and the result is exactly the frontal plane's own vertical extent in inches, **61.2″ = 5.10 ft** at 12U. The quoted −1 ft…+5 ft (72″, ≈ 0.94 : 1) assumed a taller rect than the frontal plane occupies and was never achievable alongside parity; it also predated v0.25's correction that a bounce is commonly *before the catcher*, not only out front, which argues for more catcher-side room rather than the 1 ft it allowed. Only the anchor is genuinely free, and it splits the range at **−2.5 ft … +2.60 ft**: the aft extent is fixed at 30″ in inches (the plate's whole 17″ pentagon plus 13″ behind it) because the plate is 17″ for every batter, so the profile-dependent part of the range is absorbed by the fore side. Consequence worth stating: the range moves with the batter's zone height, since the rect's aspect does — the rect is the same rect, only what fills it changes.

Dropped the **catcher position** from the top-down plane. §11.4 had called for one, but there is no rulebook position for a catcher, so any mark is invented — and rendered as an indicative arc it read as an unexplained shadow rather than a person, which is worse than absent. Nothing else needs to establish which way is behind: the plate's point does it, in both planes, because both are the catcher's view looking out at the field — which is also why the depth labels are unsigned and the `depth = 0` gridline is drawn exactly like every other gridline rather than emphasised. Also stated explicitly that the plane draws **inner and front box lines, not back or outer** — the same rule the frontal plane follows. Whether the front line is *visible* is a `RuleSet` consequence rather than a special case: baseball's box terminates 2.29 ft out front, inside the canvas, while fastpitch's reaches 4.0 ft and runs off the top edge. Drawing only the inner line left baseball's chalk stopping 0.31 ft short of the frame with nothing to say why.

Dropped the **0–2 ft / 2–4 ft / 4 ft+ depth bands** in the same breath. They assumed the un-achievable range (4 ft+ is off-canvas at +2.60), and `depth` is a continuous float that is never bucketed in storage regardless (§3.3), so the buckets were a rendering convention standing in for an axis. Replaced by a gridline every foot, labelled unsigned ("1 ft", "2 ft") on both sides — the plate sits between them, so the label does not have to carry direction.

## v0.34

Promoted §11.4's **azimuth 0** from an incidental camera parameter to a stated constraint. An off-axis camera projects the 17″ edge's two corners at different distances from centre, so `x = ±1` stops mapping symmetrically onto it and the exact-registration requirement — which the section states and the geometry tests assert — breaks. That is why the plate renders as a symmetric trapezoid with no tilt despite broadcast reference footage being shot off-axis. The reason had lived only in a code comment; the spec read as though the value were arbitrary. Also opened **Open Question #9**: should the ground perspective tilt per batter handedness? For it, the off-axis look reads more naturally and the batter does stand on one side; against it, registration breaks and the zone grid stays orthographic regardless, so only the ground furniture would tilt and risk reading as a mismatch with the grid above it. Shelved — not required for v1 or Milestone 1, and explicitly out of scope for DIA-011.

## v0.33

Trimmed §11.4's top extent from +1.80 to **+1.5** — half a zone height above the zone, ≈ 12″ over the letters, upper-face level at 12U. Above that nothing is learned: a foot over the head and two inches over the head are the same observation, and §17.4 buckets both as uncompetitive-high, so those pitches stay recordable but land unresolved on the top edge. Shoulder height (y ≈ 1.31) stays resolved, since an elevated fastball is a location rather than a miss. Canvas becomes ≈ 68″ × 61″ (≈ 1.11 : 1) and gains vertical room for the count HUD and outcome row. Also added an explicit note on **which canvas dimension binds**, because the earlier "widening is free in tap precision" claim was true only in the height-bound case: height-bound, zone px = panelHeight / verticalExtent and lateral range does not enter; width-bound (a width budget so the call column fits) zone px = panelWidth × 2 / lateralExtent and vertical extent does not enter. Worked at 1180 × 760 leaving ~450 for calls, ±4.0 with the top at +1.5 gives a 730 × 657 panel and a 182 × 258 zone versus 189 × 267 under the old ±1.9 / +1.80 frame — so reaching the batter and the full box cost ≈ 4% of zone size and ~400 px of width rather than tap precision.

## v0.32

Widened §11.4's lateral range from ±1.9 to **±4.0**, and changed its justification. Reaching the batter's-box chalk was never the requirement: a pitch may be recorded anywhere on the canvas, including at the batter, and the silhouette lays over part of it rather than the frame being sized to exclude her. A 12U stance puts her body centre ≈ 26–30″ off plate centre (x ≈ 3.1–3.5, spanning x ∈ [2.4, 4.3]), so ±4.0 leaves capture room on both sides. Widening costs nothing in tap precision — the canvas is height-limited on a tablet, so the zone's on-screen size is fixed by the vertical scale and lateral range only adds pixels beside it (*over-stated; corrected in v0.33 — this holds only when height binds, and the side-by-side layout is width-bound, where widening is exactly what costs*); what it spends is horizontal room competing with the call grid, which is why it stops short of ±6.0 (where the whole 36″ box would fit, but its outer ~20″ is chalk nobody stands in). Consequences: the canvas becomes ≈ 68″ × 68″ (≈ 1 : 1) instead of 2.1 : 1 portrait; nothing clips laterally, so the chalk band reads as a line instead of a clipped wedge and the visible inner run grows to ≈ 80″ of the 84″ box (y ∈ [−1.05, −0.363], bounded by the canvas bottom rather than the frame edge) with ≈ 25″ of the front line; the top-down plane's −1 ft…+5 ft depth range now renders at ≈ 0.94 : 1. Also: the ground-line boundary keeps the fade's inherent tonal step and **drops the drawn full-width rule** (an explicit line read as an arbitrary graphic; revisit when the hinge gives the boundary interaction weight); the shadow batter is stated to be paint that takes no pointer events, since a silhouette swallowing taps would make the region it occupies uncapturable; and the plate's on-screen depth is corrected from 0.153 to **0.152** y-units (816/5352 = 0.15247, and 0.215 × 17/24 = 0.15229 — both round to 0.152), caught by a geometry test computing from the canonical inputs rather than copying the prose.

## v0.31

Replaced §11.4's `y = −0.45` scenery cap with a distance fade. The cap had been protecting grid legibility against a busy backdrop, which a fade protects without truncating the ground furniture drawn on the receding plane; ground in front of the plate is where a bounced pitch lands and is drawn as dirt to its natural extent. Consequences: the no-chalk-above-the-ground-line rule is withdrawn, both the inner and front batter's-box chalk lines render (≈ 64″ of an 84″ box visible at the default camera rather than ≈ 24.5″), and Open Question #8 closes. Also records that the drawn ground plane above the line is geometrically invertible to a bounce depth and is deliberately not read that way — taps above `y_ground` are airborne, and depth comes only through the hinge.

## v0.30

Moved the version history out of the spec's status line into this file; the status line now carries the three most recent entries only.

## v0.29

A wording pass over §3.1, §11.1, §11.4 and §18.7 — no numbers or rules changed; rationale, correction history, and comparisons against the current build are removed, and remaining judgment calls point at Open Question #8 or the review that settled them.

## v0.28

Resolves a conflict between v0.26's chalk rule and its own no-chalk-above-the-ground-line rule: the batter's boxes lie mostly forward of the plate and therefore project above the ground line in *every* camera, so only the inner line renders and it clips at `y_ground`; box legibility joins the scenery cap as a field-test question (§9 #8, §11.4).

## v0.27

Records the pitch-canvas scenery cap as an open question rather than a settled figure — it is the one value in §11.4's geometry that is chosen rather than derived (§9 #8, §11.4).

## v0.26

Corrects the v0.25 foreshortening formula (`H/(d−17″)`, not `H/(d+17″)`; 0.215 at the default camera, not 0.19), replaces the applied ratio with a real pinhole projection, states the camera constraints as coupled, splits drawn ground from the hinge trigger and caps scenery by a `y` bound rather than by feet, fixes canonical zone-height inputs so derived values and test tolerances agree, and specifies the chalk convention (§3.1, §11.1, §11.4).

## v0.25

Makes the pitch canvas's vertical geometry derived rather than eyeballed: the ground plane is a computed `ZoneCoord` value, the plate is foreshortened by a stated virtual-camera ratio, the zone rect and call grid stay orthographic while ground furniture takes perspective, the lateral range widens to reach the batter's-box chalk, and batter's-box dimensions route through `RuleSet` (§3.1, §11.1, §11.4, §18.7).

## v0.24

Records the canvas fidelity question as an open golden-test decision rather than a settled directive (§11.4).

## v0.23

Specified the pitch canvas composition for both planes — plate anchor, batter's boxes, lateral registration, dirt band (§11.4).

## v0.22

Derives chase intent from zone position instead of storing a flag (§10.1, §17.4).

## v0.21

Unified command classification on call-zone resolution (freeform taps resolve to the containing zone, so one rubric covers both producers) and replaced "waste" terminology (§10.1, §17.4).

## v0.20

Replaced miss-distance magnitude with command classification (executed / competitive miss / uncompetitive, plus miss direction) (§17.4).

## v0.19

Adds `BounceCoord` (§3.3) and `bounceLocation` on `PitchThrown` (§4.1) for pitches that hit the dirt before reaching the plate, captured via the dirt-band hinge interaction (§11.1).

## v0.18

Allows `intendedLocation` to be captured either via the call-zone grid (centroid, `intendedZoneId` set) or as a freeform tap (`intendedZoneId` null) — see §10.1.

## v0.17

Adds `EarnedRunOverride`/`RbiOverride`, a narrow scorer-judgment exception to §13.3's earned-run/RBI derivation (§13.5).

## v0.16

Specified two-tier (per-pitch / aggregate) back-inference semantics for `CountCorrection` checkpoints (§12.5).

## v0.15

Added per-pitch batter actions (showed bunt, pulled back, slap, fake slap, slash) to PitchThrown (§4.1).
