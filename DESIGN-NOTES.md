# DESIGN-NOTES — the passes behind these templates

**What is authoritative here.** The shipped templates plus this file. Every decision below
records the panel advice it came from and whether it was **adopted**, **adapted**, or
**not adopted** (with the reason). Downstream cards should read `D1`–`D12` and
"Known gaps" as the spec; the panel's raw answers are in the traces named below.

---

## 1. The MoA design passes

Two passes were run, both with the `trio` preset (references
`nous:openai/gpt-5.5`, `nous:anthropic/claude-opus-4.8`,
`nous:google/gemini-3.1-pro-preview`; aggregator `deepseek-flash`). The advisors are
tool-less, so the prompt carried the three real instances **verbatim**: JSOM's
`tools/ci.sh` + both hooks + `.ci.env.example`, Notes' `scripts/gate.sh` + `.githooks/pre-push`,
and jsonTools' `tools/ci.sh` + `check_wiring.py` — 56 KB of prompt, six questions asked.

```bash
HOME=/home/<you> hermes --provider moa -m trio chat -Q --query-file /tmp/moa-run/moa-prompt-v2.txt
```

### Traces

| Pass | Session | Trace (JSONL) | Size |
|---|---|---|---|
| A | `20260919_102717_879ded` | `~/.hermes/profiles/hermes-dev/moa-traces/20260919_102717_879ded.jsonl` | 697,913 B |
| B | `20260919_103623_5c7df8` | `~/.hermes/profiles/hermes-dev/moa-traces/20260919_103623_5c7df8.jsonl` | 733,040 B |

Both traces hold all three reference answers in full (each 4.7–14.7 KB of prose; the
extracted copies used while writing this file are in `/tmp/moa-run/extracted/`). Pass B's
aggregate answer is also stored verbatim as `runs[0].metadata.answers` on kanban run 29 of
task `t_2cadb888`.

> **Path note.** The card said traces land in `~/.hermes/moa-traces/`. On this box they
> land in the **profile home**: `~/.hermes/profiles/hermes-dev/moa-traces/<session>.jsonl`.
> The `~/.hermes/moa-traces/` copy seen at 10:24 belongs to a different (non-profile) session.

### Why there are two

Pass A's session was tool-enabled and inherited `HERMES_KANBAN_TASK` from the worker that
spawned it, so its agent concluded it *was* the worker for this card: it answered the
consultation, then started building its own self-test sandboxes in the cwd, and had to be
stopped. Pass B was re-run from a neutral cwd with an explicit
"answer in prose, do not create or edit any file" preamble, and it delivered the
consultation cleanly. See §7 for the trap and its countermeasure.

Both consultations were real work by the advisors: the answers in pass A and pass B
overlap on the substance and differ in a few recommendations, which is why the
disagreement table in §3 cites both.

---

## 2. What the panel said, question by question (pass B, verbatim substance)

**Q1 — minimum viable kit.** *Add exactly two things*: (1) `templates/hooks/install.sh`
(copy hooks, chmod, run `git config core.hooksPath .githooks`, then print
`git config --get core.hooksPath` so the user sees it took) — "hooks are the only
component that fails OPEN"; (2) the `.gitignore` lines, **as a checklist block in
PLUNK-IN.md, not as shipped per-language dotfiles**. *Leave out*: `Makefile` (a fourth
entry point that drifts from the three canonical callers), a test-template file (a blank
test teaches nothing; the worked artifact-identity stage is the example), a `docs/` brief
template (rung 2 is per-task prose), `.ci.env.example` for deno/python (zero knobs worth
setting), per-language `.gitignore` files. And: "Do NOT add a `gates/` dir, upgrade script,
or checksum manifest — that machinery outgrows rung 5."

**Q2 — stage sets and skip-vs-fail.** The rule: *the tool that IS the job* (runtime,
compiler, test runner, build backend) **FAILS** when absent; *the tool that ADVISES*
(formatter, linter, clang-tidy, mypy) **SKIPS loudly**, with `--strict-tools` flipping it
to FAIL. Deno: env → lint → tests → format (touched) → identity. Python: preflight resolve
→ lint → format (touched) → tests → types (only when configured) → identity → build →
installed smoke, all in `mktemp -d`, never into the repo tree. C++: `build tests` for
pre-commit, `--require-clean tree format build tests version asan tsan tidy pristine` for
pre-push; **drop** `wire`/`fuzz`/`std`/`conform`/`cli`/`coverage` from the shipped default
set as project-shaped; **keep** `version`, "else the decided cpp artifact-identity
invariant is documented but not enforced — exactly the failure this kit exists to prevent."

**Q3 — python tool discovery under `python3 + uv`.** Ladder: `.venv/bin/<tool>` →
`uv run --frozen <tool>` (when the repo declares it) → `uv run --with <tool>==<pinned>` →
`python3 -m <tool>`; **print the resolution table on every run**, because "the gate passed"
and "the gate passed using a linter uv downloaded because your repo never declared one" are
different statements.

**Q4 — the C++ two-tier split.** Decide by *measured warm time*, not repo size: the fast
tier stops belonging in pre-commit when warm p95 exceeds ~15 s (proxy: 40–60 translation
units). Keep configure + build + ctest ("warm `cmake -S . -B build` is sub-second and is the
only cheap guard against 'CMakeLists edited, nobody regenerated'"); **reject** tests-only
against a stale build dir — "the trap where you commit source that does not compile because
yesterday's binary passed"; also: early-exit when no source file is touched, and say so
loudly when the build dir is cold instead of passing silently.

**Q5 — failure honesty.** "Report every failure whose result you can still trust":
independent stages accumulate; dependent stages short-circuit (configure → build →
tests/asan/cli/tidy); **ASan and pristine are independent and should still run**. Crucially,
pre-seed every requested stage and print `BLOCK <stage> (…)` lines for the ones that never
ran — "the summary currently prints 'stopped at: build' and later stages simply vanish,
which reads as 'they passed'."

**Q6 — the three rot modes.** (1) *Template drift* → a provenance line in the first lines of
every shipped script plus `--list` derived from `declare -F`; no checksum manifest.
(2) *Hooks never armed* → `install.sh`, a one-line nag when `git config --get
core.hooksPath` is unset, and **never** hijack an unrelated command to arm them.
(3) *Rationale deleted* → enforce the `INCIDENTS.md` shape in the gate and cite the
incident in every failure message.

---

## 3. Where the panel disagreed with itself

Recorded because these were the live judgement calls, and the shipped answer is in §4.

| Question | Split | Shipped |
|---|---|---|
| C++ fast tier: `build tests` or tests-only? | tests-only (one advisor) vs build+tests (two) | **build + tests**, matching pass A and pass B's Q4 |
| ruff/pytest missing: SKIP or FAIL? | SKIP (one) vs FAIL (two) | **FAIL where the tool IS the job**; the shipped python gate gets there via the uv fallback, with `STRICT_TOOLS=1` to force failure in every case (see §4) |
| Tool discovery primary: `uv run --with` or the project env? | `--with` first (one) vs project env first (two) | **project env first** (`.venv/bin` → PATH → `uv run --with`), and the choice is printed each run |
| Hooks armed by the gate or by the user? | self-arm silently (one) vs warn (two) | **user-armed only**; nothing in the kit mutates git config |
| A `tree` stage for deno/python? | yes (two) vs not mentioned | **not shipped** — the `.gitignore` block in PLUNK-IN step 3 covers the original reason, and the kept scripts stay closest to Notes' proven `gate.sh` |

---

## 4. What this kit ships versus that advice

**Adopted**
- The `.gitignore` block as a PLUNK-IN checklist (step 3), not as shipped dotfiles.
- "The runtime is not a cosmetic tool": `templates/deno/gate.sh` now fails with a clear
  reason when `deno` is absent, instead of dying inside `deno task lint`.
- `BLOCK <stage> (did not run: the run stopped at …)` lines in the C++ summary for every
  requested stage that never ran (Q5's central point).
- A provenance line in all three gate scripts and both hooks (Q6.1).
- Which runner answered, printed on every python tool invocation (Q3's "never silent").
- `--list` derived from `declare -F` in the C++ gate (already the source repos' habit).
- Dropping `wire`/`fuzz`/`std`/`conform`/`cli`/`coverage` from the C++ default set.

**Adapted**
- *`hooks/install.sh`*: **not shipped.** The layout for this card is decided, and PLUNK-IN
  step 1 is the copy-paste equivalent of that script (mkdir, cp, chmod, `git config`, and
  step 6's `git commit` proves it worked). Recorded as gap 1 below — it is the panel's
  highest-value Q1 suggestion and the obvious first follow-up card.
- *Pinning the python tools*: the gate uses unpinned `uv run --with` as its last resort and
  **prints that fact**, telling the user to add a dev dependency. A pin inside the gate would
  drift from the repo's own pin, and `--frozen` hard-fails whenever the tool is not in the
  lockfile — a gate that fails on a correctly-configured repo is worse than a loud note.
- *FAIL for a missing pytest*: the shipped gate FAILS when pytest is absent (the sandbox
  proves the real path: `.venv` is created by uv on first run, so pytest is one resolution
  away). The only case that SKIPs is "no pytest **and** no uv", with `STRICT_TOOLS=1`
  available to make any missing tool a failure.

**Not adopted**
- *Enforcing the `INCIDENTS.md` shape from the gate*: another stage's worth of machinery for
  a file that a human reads; the rationale lives inline in the scripts. Recorded as gap 7.
- *A checksum manifest / auto-updater*: needs the kit to exist on disk at run time, and the
  design's whole point is that a copied repo is self-contained.

---

## 5. Decisions taken (D1–D13), as shipped

- **D1 — No files beyond the decided layout.** Only `templates/cpp/.ci.env.example` earns an
  example file; the deno and python gates have no knobs worth configuring.
- **D2 — One gate script, two hooks, per language.** Deno/Python: the whole gate is seconds,
  so `pre-commit` runs all of it and `pre-push` runs the same file. C++: two tiers
  (`build tests` at commit; the nine-stage full run at push), because a full C++ run is minutes.
- **D3 — The artifact-identity stage replaces jsonTools' `wire` stage.** `wire` is a
  multi-binary project's problem; the portable equivalent is "two copies of one number must
  agree", exactly one per language, documented in `PLUNK-IN.md` step 4.
- **D4 — Python's clean-checkout equivalent is a fresh environment built from what the repo
  declares.** Packaged (`pyproject.toml`): build sdist+wheel, install the wheel into
  `mktemp -d`, import it, ask its console script for `--version` — that is what catches
  "works only because of the editable install". **Extended 2026-09-20** for the repo that is
  *not* packaged: with only `requirements.txt` there is no wheel to build, and inventing
  packaging metadata the repo does not have would be a different project, so the fresh
  environment is a `mktemp -d` venv with the declared requirements installed into it and the
  **suite run from that venv** (the resolved version of each declared requirement is printed,
  and a pytest missing from the list is installed for the run with a loud NOTE). Its identity
  pair is a tracked `VERSION` file ↔ the `__version__` the code reports, because a
  requirements-only repo has no packaging metadata to hold the number. Both branches share
  one rule: never from the dev tree's environment. (Added after the docsum card
  `t_8af07965`, where the wheel-only template hard-failed on a real unpackaged repo.)
- **D5 — The touched-file set always includes `git ls-files --others --exclude-standard`**,
  and falls back to the last commit on a checkout that is level with `origin/main` (and to
  the staged set on a repo with no commits at all). This is the filled example in `INCIDENTS.md`.
- **D6 — Failure honesty.** Deno and python accumulate every failure in one run; the C++
  chain stops at the first failing stage and `summary()` names every requested stage that did
  not run as `BLOCK <stage> (did not run: the run stopped at <stage>)` — the panel called these
  `NOTRUN` lines, and the shipped word is `BLOCK`; either name means the same thing, and the
  point is the same: once the build fails the later stages have nothing trustworthy to say, and
  silence reads as success. (Pass-1 advice; adopted, see `out-cpp-fail-format.txt`.)
- **D7 — Skip vs fail.** The runtime/compiler/test-runner fails when absent; cosmetic tools
  skip loudly, with `--strict-tools` / `STRICT_TOOLS=1` making every missing tool a failure.
- **D8 — Hooks are armed by the user, never self-armed.** Nothing in this kit mutates git
  config as a side effect; PLUNK-IN says to arm them once per clone, and step 6 proves the arming.
- **D9 — Every shipped script carries a provenance line**, and the C++ `--list` is derived
  from the defined stage functions so it cannot drift from what the script runs.
- **D10 — Nothing is installed into the repo tree.** Python builds and installs under
  `mktemp -d` with a trap; the C++ `pristine` stage works in a temp dir; the sandbox evidence
  lives under `/tmp/kit-selftest/`.
- **D11 — The tidy baseline is captured by the gate, never by hand, and compared normalised
  on *both* sides.** (2026-09-20, from finding 1 of card `t_561f6857`.) The kit used to
  document a one-line `grep … | sort -u` capture while the comparison stripped `:line:column`
  from the **log side only**: a baseline captured that way matched nothing, so every
  inherited finding kept counting as new and the tidy stage could never pass — a permanently
  red stage, which is a bypassed stage (`INCIDENTS.md`, Computo). Two further holes were on
  the same line (no `mkdir -p .ci`; `&&` meant a failing tidy wrote no baseline at all, and
  the build stage had to have run first), and the comparison had two more: it produced a
  false "new finding" whenever a file held two identical findings (the baseline side was
  de-duplicated and the log side was not), and it captured clang-tidy's **absolute** paths, so
  a baseline captured in one clone named nothing in a checkout at another path — the nightly
  clean-checkout caller.
  Shipped instead: the normalisation lives in exactly one place, `tidy_key` in
  `templates/cpp/ci.sh` (repo-root prefix stripped, `:line:column` stripped, one key per
  finding), applied to both operands; and the documented way to accept findings is
  `tools/ci.sh --write-tidy-baseline`, which runs the real build and tidy stages and writes
  the baseline through that same function, then tells you to commit it (a baseline that is
  neither committed nor ignored fails the tree stage). That mode prints no verdict and exits
  before the summary, so it can never read as `GATE PASSED`.
  Rejected: (a) documenting the hand-written pipeline verbatim — that is a second
  implementation of the normalisation, i.e. exactly the drift this decision removes;
  (b) dropping the normalisation and comparing raw log lines — then an unrelated edit above a
  finding reads as a new finding, and the baseline stops working on any other machine.
  Known consequence, stated rather than hidden: the comparison is line-blind, so a *second*
  identical finding in a file that already has one collapses into the first. Fix the
  baselined finding; do not grow the baseline around it.
- **D12 — In the unpackaged python branch every tool runs with the sys.path the tree declares**
  (`tool_env` → `py_env`). (2026-09-20, from card `t_561f6857`.) The tree *is* the artifact in
  that branch, so the layout it declares is the layout the gate must use: a package under
  `src/` is otherwise invisible to the `tests` stage (pytest's rootdir insertion reaches only
  the tests directory, and `python -m pytest` reaches only the repo root), which made the gate
  red on a repo whose suite was green — `INCIDENTS.md` has the measurement. The packaged branch
  deliberately keeps its own environment instead: `uv run` syncs the project, so the install is
  what the smoke and identity steps must ask about, and `PY_IMPORT_PATH` is emptied for exactly
  that reason. Rejected: a `conftest.py` `sys.path` shim per repo — that moves the gate's
  layout knowledge into every repo that copies the gate, which is the drift this kit exists to
  remove.
- **D13 — Drift between a repo's copy and the kit is caught by a probe per propagating fix,
  not by a hash and not by a diff stage.** (2026-09-20, from card `t_0cc793fb`.) A repo's
  `.ai-dev-starter.json` record answers *provenance and intent* — "what did this repo take,
  and did it adapt it on purpose?" — and it cannot answer *lateness*. That was measured
  rather than argued: on four genuine one-fix-behind copies of `tools/ci.sh`, taken from each
  repo's own history, the record's own procedure returned "nothing to do" 4/4 (the recorded
  kit hash still matched, because the kit had not moved, and the recorded repo hash still
  matched, because nobody had edited the copy). A byte-compare stage against the kit would
  have gone red on those repos the day it landed — their copies are *forks* (60, 89, 582 and
  586 differing lines: kit header replaced, stages added and dropped, repo-local defaults)
  and a fork's only explanation today is prose nothing parses — while the diff *size* inverts
  as a signal: a lagging copy is missing 27 kit lines and a verified, current record is
  missing 125. **Diff size measures divergence from the kit, not lateness.**
  Shipped instead: `probes/<slug>.sh` — one small script per kit fix, taking a gate script
  and holding it to that fix's contract by name and by behaviour, offline, no kit checkout,
  no build, under a second (reference: `probes/tidy-baseline.sh`, 7 checks) — plus
  `tools/kit-probes.sh`, the kit's own run of every probe against the file it guards, and a
  `kitprobes` stage in all three template gates that runs each script in the repo's
  `tools/kit-probes/` against *that* gate. The rule it enforces: **a fix that must propagate
  ships a probe.** Measured: the kit verifies 7/7; the four repos at HEAD verify with **no
  false positives**; the same four one fix behind report `PROBE FAILED`, rc 1.
  Rejected: (a) a byte-compare stage against the kit at `revision` — red on 4/4 immediately,
  and a fork's differences are decisions, not lag; (b) a hash-based drift check — structurally
  incapable, it never compares the repo's file against the kit's; (c) comparing line counts —
  divergence, not lateness.
  Limits, stated rather than hidden: a probe is name- and contract-level, so a semantic
  regression *inside* a function that is still present is not caught — that costs a real
  build and a real run (which is what the port card did by hand, four times); and a probe has
  to be written per fix, so this is a discipline, not a free guarantee. A copy with no
  `tools/kit-probes/` SKIPs the stage on purpose: "carries no probe yet" is not "is behind".

---

## 6. Known gaps / open questions

1. **`templates/hooks/install.sh` is not shipped** (the panel's top Q1 addition): PLUNK-IN
   step 1 is manual, and the panel's point stands — arming is the one step that fails open.
2. **Deno and python have no `tree` stage.** The C++ gate fails when its own footprint
   (`.ci-logs/`, build dirs, `.ci.env`) is not ignored; the other two rely on PLUNK-IN step 3.
3. **No `fuzz`/`std`/`conform`/`cli`/`wire`/`coverage` stages in the C++ template** — they
   are project-shaped. PLUNK-IN's appendix says what a `fuzz` stage looks like when the
   project has a target (this is Harri's standing new-project rule, so it is the first thing
   to add to a C++ plunk-in).
4. **`CI_VERSION_BINARIES` is opt-in**: the "every binary answers `--version` with the same
   number" half of the identity check is off by default, because projects name executables
   differently.
5. **No kit updater.** A copied repo owns its gate; PLUNK-IN says diff against a newer kit by
   hand (deliberately, per Q6.1/Q1).
6. **Touched-files-only formatting means pre-existing drift stays.** Deliberate (contract
   rule 6), but a repo plunking this in will have unformatted old files forever unless
   someone formats them in one commit.
7. **The `INCIDENTS.md` shape is not enforced by any gate** (panel Q6.3 suggested grepping
   for `^## YYYY-MM-DD — `). Cheap to add if a repo ever deletes its rationale.
8. **The C++ full tier runs `tidy` with no baseline by default**, i.e. zero findings
   required. A repo with inherited findings accepts them with
   `tools/ci.sh --write-tidy-baseline` (which runs the build and tidy stages, writes the
   baseline in the one form the comparison reads, and tells you to commit it — D11). The
   line-blind comparison means a second identical finding in a file that already has one is
   not distinguished from the first.
9. **Probes are per repo and per fix, and their absence is a SKIP.** The `kitprobes` stage
   checks the probes a copy actually carries, so a kit fix that shipped a probe the copy never
   took is invisible to it (the record's `kit_sha256` is what shows the kit moved on, and the
   port is a hand decision). A semantic regression inside a function that is still present is
   likewise out of reach — that needs a build and a run. Both limits are restated in D13.

---

## 7. The environment trap hit while doing this (read this before the next card)

A kanban worker that spawns `hermes chat` **leaks `HERMES_KANBAN_TASK` /
`HERMES_KANBAN_WORKSPACE` into the child**, whose system prompt then contains the kanban
worker protocol — so the child believes it is the worker for that card. That is exactly what
pass A did: it ran the consultation, then started executing the card (writing sandboxes into
its cwd), and the second pass ended by marking the card `done` with a summary about the
*consultation*. The work survived and was verified independently, but the board record was
misleading until corrected.

Countermeasure (used for pass B and recommended for any nested `hermes` session started from
a worker):

```bash
cd /neutral/empty/dir && env -u HERMES_KANBAN_TASK -u HERMES_KANBAN_WORKSPACE \
    -u HERMES_KANBAN_DB -u HERMES_KANBAN_BRANCH \
    HOME=/home/<you> hermes --provider moa -m trio chat -Q --query-file <prompt-file>
```

…and add "this is a consultation: do not create or edit any file, reply in prose" to the
prompt. The other half of the trap: **the trace is written to the profile home**
(`~/.hermes/profiles/<profile>/moa-traces/`), and a killed run writes no trace at all —
let the run finish if the trace is evidence you have to produce.
