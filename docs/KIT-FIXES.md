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

## The fixes

| Fix (the `name` a repo records) | Probe | What it changes, and the symptom when it is missing | Applies to | Kit commit that added it | Note |
|---|---|---|---|---|---|
| `tidy-baseline` | `probes/tidy-baseline.sh` | The clang-tidy baseline is captured **by the gate** (`tools/ci.sh --write-tidy-baseline`) and compared **normalised on both sides** (`tidy_key`: repo root and `:line:col` stripped, one key per finding). Missing: a baseline captured by hand matches nothing, so every inherited finding counts as new and the tidy stage can never pass — a permanently red stage, which is a bypassed stage. | C++ gate (`templates/cpp/ci.sh`) | `a6ad2ea` | D11 |
| `gate-stage-guards` | `probes/gate-stage-guards.sh` | A stage that returns non-zero without printing a verdict, and arrays declared with `local -a` but never assigned, together let bash unwind out of the stage **and out of the dispatch loop** — measured: `all 10 stage(s) passed in 0s / GATE PASSED`, exit 0, after executing 1 stage of ten, on a repo whose push then went through. Missing: a gate that reports a pass over stages it never ran. | C++ gate | `951608c` | Found while porting `tidy-baseline`, which is the mechanism paying for itself |
| `git-index-file` | `probes/git-index-file.sh` | `git commit -- <path>` exports a **temporary index** (`GIT_INDEX_FILE`) to the hook; any `git` command the gate runs in ANOTHER repository then reads this repo's entries against that repository's object store and dies on the first blob it does not have. Guards all three gates from one file (three `# guards:` lines). Missing: a pre-commit hook that fails on a repo the gate merely inspected. | C++ + deno + python gates | `f9c3300` | No repo-side change: the fix is in the gate |
| `optimized-stage` | `probes/optimized-stage.sh` | The `release` stage: the same suite built in a **second configuration** (`CI_RELEASE_BUILD_TYPE`), with its own log held to the `warning:` rule and its own build dir audited by `tree`. Missing: a gate that is green about a configuration nothing ever compiled — measured as twelve days of red Pages deploys behind a green local gate. | C++ gate | `d531a11` | D14; the port must also read the repo's `.githooks/pre-push`, which spells its own stage list |
| `release-process` | `probes/release-process.sh` | `templates/cpp/release.sh` → the repo's `tools/release.sh`: propose the next version from the commits since the last tag, draft the notes with the compatibility table, re-stamp `_Released` at publish time, and **refuse to publish** while the table is still a placeholder, the tree is dirty, or `HEAD` is not what `origin/main` has. Missing: a version declared in one file while a newer tag sits on the branch, and release notes nobody can trust. | C++ repos that tag releases | `—` (added by the commit that shipped this file — filled in the record commit that follows it) | Also needs `.release/` in the repo's `.gitignore` and `templates/cpp/version.hpp.in` wired to the `version` stage |
| `gitignore-footprint` | `probes/gitignore-footprint.sh` | The gate-footprint recipe must use **slash-free** patterns (`.ci-logs`, `build`, `build-*`). `tree` is stage 1, so on a fresh clone it asks whether those paths are ignored **before any stage has created them**, and `git check-ignore` cannot match a directory-only pattern against a path that does not exist. Missing: the first run of a fresh clone stops at stage 1 with *"the next run would fail on its own log files"* — naming a problem the reader cannot find in their `.gitignore`, because the rule is there with a trailing slash — and the second run passes, which is why it survived. | Every repo that carries the recipe (all five C++ repos did) | `—` (added by the commit that shipped this file — filled in the record commit that follows it) | D15; the change is in the repo's own `.gitignore`, not in the gate |

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
- **A deleted probe means the fix is no longer claimed.** The row goes with it.
- The reasoning behind each fix lives where the fix landed: a `D`-entry in `DESIGN-NOTES.md` where the
  choosing was the hard part, `INCIDENTS.md` where something already broke, and the probe's own header
  for what it checks and what it does not.
