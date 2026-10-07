# KIT-FIXES — every fix that must propagate, and what a repo does about it

**What this file is for.** A repo wired from this kit carries a *fork* of the templates (`jsonTools`
differs from the kit by 586 lines, JSOM by 582, Permuto by 89, Computo by 60 — measured 2026-09-20),
so no diff and no hash can separate a deliberate adaptation from a copy that is one fix behind. The
mechanism that answers it is one **probe** per fix — a small script that takes a gate script and exits
non-zero when that fix is absent, checked by name and by behaviour. The reasoning is in
`docs/KIT-REVISION-CONVENTION.md` ("So how drift is actually caught: probes"); **this file is the index
of the fixes themselves**, which is what you read before asking a repo to pull anything in.

Read it without a checkout:

```bash
git -C ~/hermes-workspace/AI-DEV-STARTER show HEAD:docs/KIT-FIXES.md
```

**A gate is a program, not a text file** — when a tool must regex your source to learn your
stages, that is a defect in the artifact: ask the gate (`tools/ci.sh --list`) rather than
knowing the spelling of the line. Measured 2026-10-06: JSOM's `tools/check_docs.py`
pattern-matched the `CI_DEFAULT_STAGES` assignment, so the `hook-tiers-agree` change below
broke every doc-table check in that repo while the list it read was unchanged.

## The fixes

| Fix (the `name` a repo records) | Probe | What it changes, and the symptom when it is missing | Applies to | Kit commit that added it | Note |
|---|---|---|---|---|---|
| `tidy-baseline` | `probes/tidy-baseline.sh` | The clang-tidy baseline is captured **by the gate** (`tools/ci.sh --write-tidy-baseline`) and compared **normalised on both sides** (`tidy_key`: repo root and `:line:col` stripped, one key per finding). Missing: a baseline captured by hand matches nothing, so every inherited finding counts as new and the tidy stage can never pass — a permanently red stage, which is a bypassed stage. | C++ gate (`templates/cpp/ci.sh`) | `a6ad2ea` | D11 **Superseded 2026-10-07** -- the probe is retired (its subject, the copied gate file, no longer exists anywhere on the fleet); see "Retired fixes" below for where the guarantee lives now. |
| `gate-stage-guards` | `probes/gate-stage-guards.sh` | A stage that returns non-zero without printing a verdict, and arrays declared with `local -a` but never assigned, together let bash unwind out of the stage **and out of the dispatch loop** — measured: `all 10 stage(s) passed in 0s / GATE PASSED`, exit 0, after executing 1 stage of ten, on a repo whose push then went through. Missing: a gate that reports a pass over stages it never ran. | C++ gate | `951608c` | Found while porting `tidy-baseline`, which is the mechanism paying for itself **Superseded 2026-10-07** -- retired; the guarantee is the engine's runner, see "Retired fixes" below. |
| `format-checks-staged-deno` | `probes/format-checks-staged-deno.sh` | The same contract for the deno template: `deno fmt --check` reads files FROM DISK while a commit records the INDEX, so a staged-then-reformatted file passes and the commit lands unformatted text. Mechanism differs from the C++ fix: `deno fmt --check` has no stdin mode (`--check --ext ts -` returns 0 even for unformatted input, measured on 2.9.6), so the staged blob is tested with the formatter as a pure function -- format the text, compare it to itself -- and `deno fmt` reads `deno.json` from the CURRENT DIRECTORY, which is the repo root inside the gate (measured: a 95-column line stays one line there and wraps to seven in /tmp). The touched set also gains `git diff --cached --name-only`, without which a staged-only change is invisible and the stage reports "nothing to check". | Deno gates with a `deno fmt` stage | `9e73c6c` | Measured 2026-10-06: reproduced in clones of Notes and TNGPlaylists (each gate passed while its index held unformatted text), then fixed; the probe fails only P1 against both pre-fix copies. **Superseded 2026-10-07** -- retired; the guarantee is the deno repos' `scripts/format.sh`, see "Retired fixes" below. |
| `format-checks-staged` | `probes/format-checks-staged.sh` | The `format` stage must check **what a commit would record**, not only the working tree. clang-format reads files from disk; `git commit` records the **index** — so a file staged unformatted and then formatted on disk (what anyone does after this very stage rejects a commit) passes while the commit lands the unformatted text. HEAD then differs from the working tree and the next `--require-clean` push dies in `tree` with "uncommitted changes to tracked files", a message naming no formatting problem at all. The same fix adds `git diff --cached --name-only` to the stage's touched set: a staged-only change was previously invisible to it (`git diff HEAD` compares the working tree, which skips the index). | C++ gates with a `format` stage | `96719c4` | Measured 2026-10-06: reproduced in a throwaway clone, then fixed; the probe's P1 fails on every pre-fix copy it was run against. **Superseded 2026-10-07** -- retired; the guarantee is each repo's `scripts/format.sh`, see "Retired fixes" below. |
| `git-index-file` | `probes/git-index-file.sh` | `git commit -- <path>` exports a **temporary index** (`GIT_INDEX_FILE`) to the hook; any `git` command the gate runs in ANOTHER repository then reads this repo's entries against that repository's object store and dies on the first blob it does not have. Guards all three gates from one file (three `# guards:` lines). Missing: a pre-commit hook that fails on a repo the gate merely inspected. | C++ + deno + python gates | `f9c3300` | No repo-side change: the fix is in the gate. **Superseded 2026-10-07** -- retired; the guarantee is `unset GIT_INDEX_FILE` in each converted repo's gate entry point, see "Retired fixes" below (the ENGINE does not own it -- measured). |
| `optimized-stage` | `probes/optimized-stage.sh` | The `release` stage: the same suite built in a **second configuration** (`CI_RELEASE_BUILD_TYPE`), with its own log held to the `warning:` rule and its own build dir audited by `tree`. Missing: a gate that is green about a configuration nothing ever compiled — measured as twelve days of red Pages deploys behind a green local gate. | C++ gate | `d531a11` | D14; the port must also read the repo's `.githooks/pre-push`, which spells its own stage list. **Superseded 2026-10-07** -- retired; the guarantee is the `release` stage a converted repo declares in its own `gate.toml`, see "Retired fixes" below. |
| `release-process` | `probes/release-process.sh` | `templates/cpp/release.sh` → the repo's `tools/release.sh`: propose the next version from the commits since the last tag, draft the notes with the compatibility table, re-stamp `_Released` at publish time, and **refuse to publish** while the table is still a placeholder, the tree is dirty, or `HEAD` is not what `origin/main` has. Missing: a version declared in one file while a newer tag sits on the branch, and release notes nobody can trust. | C++ repos that tag releases | `b1d83f4` | Also needs `.release/` in the repo's `.gitignore` and `templates/cpp/version.hpp.in` wired to the `version` stage |
| `gitignore-footprint` | `probes/gitignore-footprint.sh` | The gate-footprint recipe must use **slash-free** patterns (`.ci-logs`, `build`, `build-*`). `tree` is stage 1, so on a fresh clone it asks whether those paths are ignored **before any stage has created them**, and `git check-ignore` cannot match a directory-only pattern against a path that does not exist. Missing: the first run of a fresh clone stops at stage 1 with *"the next run would fail on its own log files"* — naming a problem the reader cannot find in their `.gitignore`, because the rule is there with a trailing slash — and the second run passes, which is why it survived. | Every repo that carries the recipe (all five C++ repos did) | `acced82` | D15; the change is in the repo's own `.gitignore`, not in the gate |
| `hook-tiers-agree` | `probes/hook-tiers-agree.sh` | The two hook tiers were written down twice each — the gate's default list, the gate's header comment, `PLUNK-IN.md`'s table, and each hook's own argument list — so nothing could notice them disagreeing, and they did. Measured in FSMTable: the gate's list had gained `fuzz` (a stage its SPEC requires) and `lint`, while the installed `pre-push` still named the kit's original eleven, so **every push ran one stage fewer than a hand run and the stage it skipped was the fuzzer**; in FSMgine the header comment documented eight stages while the hook ran fourteen. The same day the fast tier (`build tests`) passed a commit whose files `clang-format` would have rewritten, which is why that commit had to be amended after it was pushed. Missing: a gate that reports a pass over the stages it ran while the hook guarding publication runs a different set. | C++ gate + both hooks + `PLUNK-IN.md` | `d888e29` | D16. The fast tier gains `format` — measured 1 s on a warm tree, and it is the check that bit us. Ships with a one-line change to `probes/optimized-stage.sh`, whose R5 read `CI_DEFAULT_STAGES` literally and now resolves `:-$CI_FULL_STAGES`: without that, this fix turns an existing probe red, which is this table's own contract working. **Superseded 2026-10-07** -- retired; the guarantee is structural (each hook NAMES a tier of `gate.toml`), see "Retired fixes" below. |

## Retired fixes — the probes whose subject no longer exists (2026-10-07)

A probe takes **a gate script** and checks that one kit fix is in it. (The `templates/...` paths in
the "Applies to" column above are as of each fix's own date: the gate templates moved to `examples/`
on 2026-10-07 — see `examples/README.md` — and the rows are left reading as they read when they were
written.) On 2026-10-06 every gated
repo on this fleet stopped having a gate script: the gate is `gate.toml` (policy) run by `kit-ci`
(the engine), and the stage bodies are `scripts/*.sh` — none of which is a gate the kit ships.
Measured (Permuto, the precedent this table was built on): the old probes were GREEN against
`tools/ci.sh` immediately before its conversion and, run after it against the new entry point
`scripts/gate.sh`, read `format-checks-staged` GREEN, `git-index-file` GREEN,
`gate-stage-guards` RED, `hook-tiers-agree` RED, `tidy-baseline` RED — **and both GREENs are
accidents of how those two probes SEARCH, not measurements of the new gate.** A probe whose
verdict is accidental is the failure mode this whole kit exists to remove, so the probes went
rather than the evidence.

**The guarantees did NOT go.** Each one is now held in an existing place — no new tool was built
and the engine is unchanged at v1.1:

| Probe retired | The guarantee it held | Where it lives now | The command that shows it |
|---|---|---|---|
| `probes/tidy-baseline.sh` | the tidy baseline is captured by the gate and compared **normalised on both sides** | one normaliser per converted repo, applied to both operands by the tidy stage and by the baseline writer (`scripts/gate-env.sh` + `scripts/tidy.sh`; `scripts/write-tidy-baseline.sh` in Permuto; FSMgine's stage is named `lint`) | `grep -l tidy_key ~/hermes-workspace/*/scripts/*.sh` |
| `probes/gate-stage-guards.sh` | a stage that dies without a verdict must fail the run, never be reported as passed | **the engine's runner** (`kit-ci`): every declared stage is executed and a non-zero exit is a failure, and a tier that resolves to no stages is exit 2, never a pass | `cd ~/hermes-workspace/KitCI && ./build/kitci_tests --gtest_filter='RunnerTest.FailsAndKeepsGoing:RunnerTest.ExitFiveIsFailureWithExitFailOn'` (64 tests pass) |
| `probes/format-checks-staged.sh` | the format stage checks **what a commit would record**, not just the working tree | the format stage's own script in every converted repo (`scripts/format.sh`, the staged-copy block) | `grep -l 'diff --cached' ~/hermes-workspace/*/scripts/format*.sh` (11 repos) |
| `probes/format-checks-staged-deno.sh` | the same contract for the Deno gate | the same place — Notes and TNGPlaylists each carry it in `scripts/format.sh` | as above |
| `probes/git-index-file.sh` | git's temporary index must not reach anything the gate runs | `unset GIT_INDEX_FILE` in each converted repo's gate **entry point** (`scripts/gate.sh`, plus `scripts/gate-env.sh` so a stage that sources neither is still covered). **The engine does NOT do this** and must not: it runs `/bin/sh -c` with the inherited environment. docsum and Notes carry no unset line and are not exposed — measured: every `git` call in their stage scripts reads their OWN repository, and the defect needs a `git` command in a *different* repository | `grep -rn GIT_INDEX_FILE ~/hermes-workspace/*/scripts/*.sh` (8 repos) |
| `probes/hook-tiers-agree.sh` | the hooks and the gate must name the same tiers | structural: a converted repo's `.githooks/` **names a tier** of its own `gate.toml` and holds no stage list, so the two cannot disagree; `kit-ci --list` prints the tiers the hooks name | `grep -rn -- '--tier' ~/hermes-workspace/*/.githooks/` — 11 repos, every hook on the fleet names a tier and none names a stage list (the mechanical check the retirement asked for) |
| `probes/optimized-stage.sh` | the suite is built and tested in a **second configuration** | the `release` stage each converted repo declares in its own `gate.toml`, whose body is `scripts/release.sh` reading `CI_RELEASE_BUILD_TYPE` | `grep -rln CI_RELEASE_BUILD_TYPE ~/hermes-workspace/*/scripts/*.sh` (Computo, FSMTable, FSMgine, JSONFuzz, UnicodeChecker) |

Two probes were **not** retired, because their subject is not a gate script and still exists:

- `probes/release-process.sh` guards `templates/cpp/release.sh` — the release process is still a
  copied artifact (five repos carry `scripts/release.sh` / `tools/release.sh` today).
- `probes/gitignore-footprint.sh` guards `PLUNK-IN.md` step 3 and a repo's own `.gitignore` —
  both still ship.

Which is why the rule in `PLUNK-IN.md` step 9 is still the rule: **a fix that must propagate ships
a probe** — but only a fix to an artifact a repo still *copies*. The seven above are not that any
more: their subject is a file nobody copies, and their guarantees are held by the engine, by a
named stage script in each repo's own policy, or structurally.

## How a repo adopts a row (what to ask the assistant for)

Per fix, in the repo, in this order:

1. **Decide.** Read the row's "What it changes" and "Applies to". If it does not apply, or you decline
   it, that is a recorded answer too — see step 4.
2. **Port the change.** For most fixes that means the gate script (or, for `gitignore-footprint`, the
   repo's own `.gitignore`). Copy the probe into the repo:
   `cp "<kit>/probes/<slug>.sh" tools/kit-probes/<slug>.sh` — `tools/kit-probes/` **is** the list of
   fixes the copy claims to carry, and the gate's own `kitprobes` stage runs everything in it on every
   full-tier run.
3. **Prove the fix, not the spelling.** Run the probe against the repo's gate and require
   `PROBE VERIFIED`: `bash tools/kit-probes/<slug>.sh tools/ci.sh .` (a repo's `kitprobes` stage passes
   the gate script; the kit passes the guarded file — `probes/<slug>.sh` handles both). Then run the
   gate itself: a probe is name- and contract-level and cannot see a regression *inside* a function that
   is still present.
4. **Record it.** In `.ai-dev-starter.json`: `adopted_fixes[]` with `name`, `from_revision` (the kit
   commit in the last column), `probe`, and `adopted_in` filled by the record-only commit that follows
   the port. A fix you decided against goes in `declined_fixes[]` with a one-line `why` (with the
   measurement, if there is one). **Porting is two commits** — the artifact commit, then a record-only
   commit that names it — because a commit cannot name itself. The full shape and the two rules that
   bite (`revision` moves re-read EVERY `kit_sha256`; `adopted_in` is stored short) are in
   `docs/KIT-REVISION-CONVENTION.md`.

## Keeping this table true

- **A fix that must propagate ships one commit: the fix, its probe, and its row here.** Nothing else in
  that commit; a repo's `from_revision` then names exactly one thing.
- **`added_in` for a new row is written by the record-only commit immediately after it** — the same
  two-commit shape a repo uses, for the same reason.
- **A deleted probe means the fix is no longer claimed.** The row goes with it. **Exception, added
  2026-10-07:** a probe deleted because its *subject* stopped existing fleet-wide keeps its row with
  a "Superseded" note in the Note column, because the guarantee did not go — it moved, and "Retired
  fixes" above is the index of where. A row is deleted only when the guarantee itself is gone.
- The reasoning behind each fix lives where the fix landed: a `D`-entry in `DESIGN-NOTES.md` where the
  choosing was the hard part, `INCIDENTS.md` where something already broke, and the probe's own header
  for what it checks and what it does not.
