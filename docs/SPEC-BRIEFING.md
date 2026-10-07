# SPEC-BRIEFING — how to brief a build so the agent cannot invent scope

**What this is.** Rung 2 of the ladder ("write a brief before delegating"), in the shape that
has carried two multi-sitting agent builds end to end: `fsmTable` (first) and `KitCI` (four
sittings, a frozen `SPEC.md`, zero rework from independent verification). The brief is one
committed file the agent works from and you rule on. It is not prose about the goal — it is
the frozen contract the agent's output is checked against.

## The five things a brief freezes

1. **The vocabulary.** Every concept the build introduces gets a name and a one-line
   definition, before any code. A word the brief does not define is a word the agent defines
   for you — differently in each sitting.
2. **The test list.** Name the tests (or the behaviours) up front. The agent writes them
   first, so a missing behaviour shows up as a gap in the list rather than as a missing diff.
3. **The evidence rule.** *A claim you cannot back with gate output is not a result.* Every
   "done", "works" and "fixed" names the command that shows it and the output it printed.
   This is the rule that makes the other four checkable.
4. **`QUESTIONS.md`.** Where an ambiguity blocks progress, the agent records the reading it
   took and why, and keeps going. You rule on each entry in the file (ruling, date, who); the
   ruling is binding from then on.
5. **`REPORT.md`.** The only narration. One shape, every sitting: what landed, the command
   that proves it, what did not land, what is still open. Status is never taken from anything
   else.

## The ruling loop is the point

The agent does **not** stall on every ambiguity and does **not** guess silently: it writes
the question, the reading it took, and the evidence for that reading, then proceeds. You
answer on the card or in the file. Measured effect (KitCI, Q23): the agent **fact-checked its
patron's claims** against the referenced tool's own docs — a sharper README sentence that
pre-commit's docs did not support — and narrowed the claim instead of shipping it. That is
the rules working, not luck.

## `REPORT.md`'s two honesty rules, both observed on KitCI

- A test that passes **for the wrong reason** is recorded as such and **excluded from the
  count** of TDD witnesses, rather than counted to make the number look better.
- A check that was **skipped** is reported as skipped. "The gate passed" and "the check that
  would have failed never ran" are different statements.

## For a conversion, the equivalence claim needs its own measurement

When the brief is "replace X with Y, keeping the behaviour", *"Y does what X did"* is itself a
claim under rule 3 — it needs a measurement, not an argument. Run what checked the old
artifact against the new one and report both results. On the Permuto conversion, running the
old checker's own probes against the new entry point is what turned "we declined five checks"
into a measured statement about where each of the five contracts went.

## What this brief is not

- Not a design doc. Decisions it does not make are the agent's, recorded in `QUESTIONS.md`,
  and ruled on by you.
- Not per-sitting. One brief spans the build; a brief rewritten every sitting is the
  scope-invention it exists to prevent.
- Not long. fsmTable's and KitCI's are about a page each — length is context the agent pays
  on every run.
