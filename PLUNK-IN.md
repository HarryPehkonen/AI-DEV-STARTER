# PLUNK-IN — upgrading an existing repo to rung 5 in one sitting

Copy-paste, in order. Nothing here needs network access, an account, or a CI service.
Everything lands in the repo itself; there is no second place to look.

```bash
# set this once per shell
KIT=~/hermes-workspace/AI-DEV-STARTER   # this kit — every step below names its own files
```

Work on a branch, not on `main`:

```bash
git checkout -b process/plunk-in-the-gate
```

---

## Step 0 — look before you touch

```bash
git status --short              # know what is already uncommitted
git log --oneline | head -5     # the gate's "touched files" base is origin/main or HEAD
```

The gate checks **the files the branch touches** for formatting, so pre-existing
violations in untouched files will not block you — that is deliberate. It also means the
first run is not a full audit; it is a check on what you change from now on.

---

## Step 1 — the two hooks

The hooks are the gate's two callers (step 2). They are tracked, so the policy travels with the
clone, and they **name a tier** rather than repeating a stage list — a list repeated in a hook is a
copy nothing compares, and this kit has an incident from exactly that (`INCIDENTS.md`,
`hook-tiers-agree`).

```bash
mkdir -p .githooks
cp <converted-repo>/.githooks/pre-commit .githooks/pre-commit
cp <converted-repo>/.githooks/pre-push   .githooks/pre-push
chmod +x .githooks/pre-commit .githooks/pre-push

# arm them in THIS clone (git never copies hooks for you)
git config core.hooksPath .githooks
```

Take them from a repo that is already converted (`docsum` is Deno/Python, `Permuto` is C++), not
from this kit: the kit's own `examples/hooks/` pair is the OLD shape, which dispatches to a
`tools/ci.sh` and passes the tier as a positional word. Take a gate from `examples/` (step 2) and
you want that pair; take the engine and you want a converted repo's.

> **The one step nothing enforces.** A fresh clone has to run
> `git config core.hooksPath .githooks` again, and forgetting it is silent. The
> countermeasure is the clean-checkout run in step 7 (a clone that forgot the hooks still
> gets gated by the nightly job) plus a line in `CLAUDE.md`.

---

## Step 2 — the gate: one engine per machine, one policy per repo

The gate is two halves, and only one of them is per repo:

- **the policy is `gate.toml`, in the repo** — the stages, the tiers and their failure rules;
- **the engine is `kit-ci`, one binary per machine**, installed once and never committed.

Install the engine (Release: it is the binary every gate on the machine runs — measured 351,456
bytes installed, against the Debug build's 3,008,096):

```bash
cmake -S ~/hermes-workspace/KitCI -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release
cmake --install build-release --prefix ~/.local      # -> ~/.local/bin/kit-ci
```

Then three things in the repo, copied from one that is already converted — `docsum` (Python),
`Permuto` and `jsonTools` (C++), `Notes` and `TNGPlaylists` (Deno). **KitCI's own
`~/hermes-workspace/KitCI/docs/GETTING-STARTED.md` is the adoption guide now**; read it for the
option list, and use this for the shape:

```bash
mkdir -p scripts
cp <converted-repo>/gate.toml        gate.toml
cp <converted-repo>/scripts/gate.sh  scripts/gate.sh
cp -r <converted-repo>/.githooks     .githooks
chmod +x scripts/gate.sh
git config core.hooksPath .githooks  # per clone — step 1
```

`scripts/gate.sh` is a wrapper of a few lines: `cd` to the repo root, `unset GIT_INDEX_FILE`, fail
loudly if `kit-ci` is not installed, else `exec kit-ci --tier "${GATE_TIER:-full}"`. **Changing the
gate means editing `gate.toml`, not the wrapper.** Two converted copies predate the `unset` line
(`docsum` and `Notes`); add it when you take a copy that is missing it — the reason is below, and the
repos exposed to the defect are the ones whose stages run `git` in *another* repository.

Then edit `gate.toml` for this repo. A stage is a name and a `cmd`; a stage that needs more than one
command gets a script next to it, which is what makes the old stage bodies move over intact:

```toml
[gate]
repo = "myrepo"

[tier.fast]
stages = ["format", "build", "tests"]     # the commit path: seconds, not minutes

[tier.full]
stages = ["*"]                            # every declared stage, in declaration order

[stage.format]
cmd = "scripts/format.sh"
when = "tool:clang-format"                # a tool that is missing SKIPS the stage; it cannot fail it
```

Five rules that follow from the engine, each with a home in this kit's incidents:

- **The hooks NAME a tier** (`--tier fast`, `--tier full`); the engine has no stage-selection flag.
  The old `tools/ci.sh fuzz` is now `scripts/fuzz.sh` — the same script the stage runs, with the
  same environment (`CI_FUZZ_SECONDS=1800 scripts/fuzz.sh`).
- **`--require-clean` has no flag either.** The pre-push hook exports `CI_REQUIRE_CLEAN=1` and the
  repo's own tree stage reads it. A hand run is never required to be clean.
- **`unset GIT_INDEX_FILE` belongs in `scripts/gate.sh`** (a converted repo's `scripts/gate-env.sh`
  carries the long note). `git commit -- <path>` hands the hook a TEMPORARY index, and any `git`
  command the gate runs in ANOTHER repository then dies on the first blob it does not have. The
  engine does not do this for you — it runs `/bin/sh -c` with the environment it inherited.
- **Read the gate instead of knowing it:** `kit-ci --list` (stages, tiers), `kit-ci --graph` (the
  flow), `kit-ci --ast` (the parsed config as JSON). A tool that learns your stages by regexing a
  file is a tool that breaks when the file is edited — ask the gate.
- **Exit codes:** `0` every stage passed, `1` a stage failed (and every stage still ran — the engine
  never stops at the first failure), `2` nothing ran: unreadable or invalid config, or a tier that
  resolved to no stages.

---

### The no-engine fallback — the bash gates in `examples/`

Use this only on a machine that cannot build the engine. Everything below describes the OLD path:
a gate you copy into the repo and then own, which is a *fork* — measured, the four real C++ forks
drifted from the kit by 60, 89, 582 and 586 lines, and that is why the fleet moved on
(`examples/README.md`). The files are still maintained and the probes that guard them still ship;
`examples/README.md` says what each one is and which hooks pair with it.

#### Deno

```bash
mkdir -p scripts
cp "$KIT/examples/deno/gate.sh" scripts/gate.sh
chmod +x scripts/gate.sh
```

The gate expects these `deno.json` tasks (add whichever are missing — the gate calls
them by name, so a task that does not exist is a gate failure, not a skip):

```json
{
  "tasks": {
    "lint": "deno lint",
    "test": "deno test",
    "fmt": "deno fmt"
  }
}
```

#### Python

```bash
mkdir -p scripts
cp "$KIT/examples/python/gate.sh" scripts/gate.sh
chmod +x scripts/gate.sh
```

The gate works out which kind of Python repo it has, and prints the branch it took on its
first line (`== python gate: packaged branch, tier=full, repo <sha>`):

- `pyproject.toml` present → **packaged**: the clean-environment step builds sdist + wheel,
  installs the **wheel** into a throwaway venv, and asks *that* venv what version it is;
- only `requirements.txt` → **unpackaged**: there is no wheel to build, so the clean
  environment is a throwaway venv with the declared requirements installed into it, and the
  **suite runs from that venv** — which is what proves the declared list is complete. The
  tools run with the tree's own layout on `sys.path` (a package under `src/` is importable);
- neither file → FAIL: nothing could be rebuilt, installed, tested or identified.

The gate finds its tools as `.venv/bin/<tool>` → `<tool>` on `PATH` →
`uv run --with <tool>`. So it works on a bare machine with only `python3` and `uv`, and
it uses your project venv when there is one. `uv` is the recommended install:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh    # if uv is not already there
```

#### C++

```bash
mkdir -p tools
cp "$KIT/examples/cpp/ci.sh" tools/ci.sh
cp "$KIT/examples/cpp/.ci.env.example" .ci.env.example
chmod +x tools/ci.sh
```

Then make the gate fit the project (both are one-line edits):

```bash
# 1. the test runner: ctest is the default (add_test()/CTest). A project with its own
#    suite instead:
#      CI_TEST_CMD="./\$CI_BUILD_DIR/my_tests"
cp .ci.env.example .ci.env        # optional; every knob has a default in ci.sh
$EDITOR .ci.env

# 2. the source globs the format and tidy stages own, if your layout differs
#      CI_SOURCE_GLOBS="'src/*.cpp' 'include/mylib/*.hpp'"

# 3. the SECOND configuration the `release` stage builds and tests. The default is
#    Release, which is what a pipeline that passes no build type usually ends up
#    building; point it at whatever YOUR pipeline builds, so the gate checks the
#    configuration that actually ships rather than a second guess at it.
#      CI_RELEASE_BUILD_TYPE=Release
```

Two configurations, two knobs: every stage except `release` builds `CI_BUILD_TYPE`
(`Debug` by default), and `release` builds `CI_RELEASE_BUILD_TYPE` in its own build dir.
One configuration is not enough — a `warning:` that exists only under `-O2`/`-O3`, or code
that only misbehaves once `NDEBUG` removes the asserts, is invisible to a gate that never
configures that way, and the repo's own pipeline is the one that decides. Both build dirs
(`build*`) must be in `.gitignore` (step 3).

C++ is the one language with two tiers, because a full run is minutes and a commit
cannot afford minutes:

| Tier | Hook | Stages | Cost |
|---|---|---|---|
| fast | `pre-commit` | `format build tests` | ~6 s on a warm build dir |
| full | `pre-push` | `--require-clean tree format kitprobes build tests release version asan tsan tidy pristine` | minutes |

Both lists live in `tools/ci.sh`, as `CI_FAST_STAGES` and `CI_FULL_STAGES`, and the hooks pass the
word `fast` or `full` rather than a list of stages — so a stage added to a repo's gate (a fuzzer,
say: append it to `CI_FULL_STAGES`) reaches the hook without the hook being edited.
`probes/hook-tiers-agree.sh` checked the two lists against the code and against this table; it is one
of seven gate probes retired on 2026-10-07 (`docs/KIT-FIXES.md` → "Retired fixes"), because in the
engine's world the hooks name a tier and hold no list at all. If you take a bash gate from
`examples/`, they are recoverable from this kit's history — see `examples/README.md`.

---

## Step 3 — gitignore the gate's own footprint

The C++ gate's `tree` stage fails when the gate's own output would show up as untracked
files, so these must be ignored **before** the first run:

```bash
cat >> .gitignore <<'EOF'

# the gate's own footprint
#
# No trailing slashes, and that is the whole point: `tree` runs before the stages that
# create these paths, and `git check-ignore` cannot match a directory-only pattern against
# a path that does not exist yet — so `build/` reads NOT ignored on a fresh clone's first
# run and passes on the second. (The kit guards this with probes/gitignore-footprint.sh.)
.ci-logs
build
build-*
.ci.env

# python
.venv/
__pycache__/
*.egg-info/
.pytest_cache/
.mypy_cache/
.ruff_cache/

# deno
# (nothing: deno.lock belongs in git)
EOF
```

---

## Step 4 — point the artifact-identity check at YOUR pair

Every project gets exactly one "two copies of one number must agree" check. Pick the pair
that already exists in this repo, and set it in one of three ways. Whichever half you took, the check
is a **stage**: in a converted repo its knobs live in that stage's own script (`scripts/identity.sh`,
`scripts/version.sh`) and the shared `scripts/gate-env.sh`; the names below are the ones the bash gate
uses, and the converted repos kept them as the stage scripts' names (`examples/README.md`).

| Language | Default the gate checks | Change it by |
|---|---|---|
| Deno | `public/version.js` `APP_VERSION` ↔ `sw.js` `CACHE_NAME` | `VERSION_FILE=`/`CACHE_FILE=` at the top of `scripts/gate.sh` |
| Python, packaged (`pyproject.toml`) | `pyproject.toml` `version` ↔ `__version__` of the installed wheel | nothing to set — it finds the package under `src/` or the repo root |
| Python, unpackaged (`requirements.txt`) | the tracked `VERSION` file ↔ `__version__` the code reports | `IDENTITY_FILE=` (default `VERSION`), and `IDENTITY_IMPORT_NAME=` when the repo has more than one package |
| C++ | `project(VERSION)` ↔ the CMake-generated header | `CI_VERSION_HEADER=...` in `.ci.env` (a tracked header works too) |

A requirements-only repo has no packaging metadata to hold the number, so its declared copy
is a tracked file holding the version on a line of its own. The gate **fails** when that file
is missing rather than skipping the check: create it (or point `IDENTITY_FILE` at the file
that already holds the number) — deleting the stage needs the `INCIDENTS.md` entry below.

If this repo has no such pair (e.g. a library with one version and no cache), delete that
stage — and write the incident entry in `INCIDENTS.md` saying why, so the next person
knows it was a decision and not an oversight.

---

## Step 5 — the three documents that make the rest stick

```bash
cp "$KIT/templates/CLAUDE.md.template" CLAUDE.md   # fill in every <placeholder>
cp "$KIT/INCIDENTS.md" .                           # keep the example, add your own
```

`CLAUDE.md` must name the real commands (the gate among them) and start a **gotchas**
list. Its first entry should be the thing that has already bitten this repo — you know
what it is.

The third document is `REVIEW.md`, and it is the one that changes behaviour:

```bash
cp "$KIT/templates/REVIEW.md.template" REVIEW.md   # fill in the gate command
```

Every diff gets reviewed — by a human, or by an assistant you hand it to — and `REVIEW.md` is
what that reviewer reads first: run the gate and report it rather than repeat it; report few
findings and stand behind each one; read the call sites before claiming anything that is not
local; and reproduce a finding before relaying it. It also states what those clauses are
worth (one diff, two arms, one run each — a signal, not a proof), so the next person can
weigh them instead of trusting them. Hand the clauses over **in the prompt**, next to the
diff: a standard that stays in a document is a standard that never changes a review.

**When the job is an agent build, the brief is the document that matters.** A multi-sitting
feature is briefed, not described: frozen vocabulary, a frozen test list, a `QUESTIONS.md`
with the owner's rulings in it, a `REPORT.md` as the only narration, and the rule *a claim you
cannot back with gate output is not a result*. That shape is `docs/SPEC-BRIEFING.md` in this
kit; two agent builds have run on it (`fsmTable`, `KitCI`) with zero rework from independent
verification. Unlike the three above, the brief itself is not copied from the kit — it is
written per build.

---

## Step 6 — first run: make it pass on the committed tree

```bash
scripts/gate.sh          # or: tools/ci.sh   (C++)
git status                        # nothing modified by the gate? good
```

Expect the first run to find real problems. Handle them in this order:

1. **Fix them**, if the fix is small.
2. **Record them as accepted findings**, if they are pre-existing and large — the C++ tidy baseline
   exists for exactly this: run `tools/ci.sh --write-tidy-baseline` and commit the file it writes
   (a converted repo runs the same idea as its own stage script,
   `scripts/write-tidy-baseline.sh`, with the normaliser in `scripts/gate-env.sh`).
   (`CI_TIDY_BASELINE` in `.ci.env.example` explains why the file's form matters and how the
   comparison reads it.)
3. **Never** weaken the gate to reach green. A check that is wrong gets deleted *with an
   incident entry*, not silently.

Then commit — and let the hook run it again, so you know the hook itself works:

```bash
git add -A
git commit -m "process: plunk in the gate (rung 5)"
```

If the commit succeeded, the gate is armed in this clone. If it failed, the hook found
something the hand run did not (usually uncommitted or new files) — read the output, that
is the hook doing its job.

---

## Step 7 — the third caller: a clean checkout

The same script must run on a fresh clone, or "the gate passed" only means "it passed on
a machine that has been set up for months". This is also the diagnosis for "it works on
my machine":

```bash
# one-shot: prove the COMMITTED tree is complete and green
tmp=$(mktemp -d) && git clone -q . "$tmp/checkout" && cd "$tmp/checkout" \
  && scripts/gate.sh && cd - >/dev/null && rm -rf "$tmp"
```

Make it recurring (rung 8) on whatever host is always up, and keep it **silent when
healthy**:

```bash
# cron, nightly: prints nothing on success
0 4 * * * cd /path/to/checkout && git pull -q && ./scripts/gate.sh | tail -1 | \
  grep -q 'GATE PASSED' || echo "gate FAILED on $(hostname) $(date)"
```

The C++ gate has this built in as its `pristine` stage: `git archive HEAD` into a temp
dir, then configure, build and test there. It is the same idea without needing a cron.

---

## Step 8 — the habit that keeps it alive

Every time something breaks, in this order:

1. Fix it.
2. Add the check that would have caught it — usually a contract test, sometimes a stage.
3. Write the incident at the top of `INCIDENTS.md`: symptom, the check, and **why the
   check must stay**.
4. Append the one-line gotcha to `CLAUDE.md`.

The third line is the one that gets skipped, and it is the one that matters: it is what
stops the check being deleted six months from now by someone who sees no reason for it.

---

## Step 9 — keep a copied artifact true to the kit: probes

**This step covers the artifacts a repo still copies** — `templates/cpp/release.sh`, the two document
templates (`CLAUDE.md.template`, `REVIEW.md.template`) and the `.gitignore` recipe. It does **not**
cover the gate: since 2026-10-06 there is no gate file to copy, so there is nothing to drift — and
the seven probes that existed to hold a copied gate are retired, each guarantee traced to where it
lives now in `docs/KIT-FIXES.md` → "Retired fixes".

Copies do not sync. A defect fixed in the kit stays live in every repo that copied that file
earlier — which is how one broken clang-tidy baseline recipe was found four separate times
before anyone noticed it was one bug. The rule that closes that class:

> **A fix that must propagate ships a probe.**

A probe is a small script in the kit's `probes/` that takes a copied file and exits non-zero
when ONE kit fix is absent from it — checked **by name and by behaviour**, not by hash and not
by diff. Two ship today: `probes/release-process.sh` (guards `templates/cpp/release.sh`, `PLUNK-IN.md`
step 10) and `probes/gitignore-footprint.sh` (guards the step-3 recipe and your `.gitignore`). To
carry one:

```bash
mkdir -p tools/kit-probes
cp "$KIT/probes/release-process.sh" tools/kit-probes/   # one file per fix you carry
bash tools/kit-probes/release-process.sh tools/release.sh .
```

`tools/kit-probes/` **is the list of fixes your copy claims to carry**. (The index of the fixes
themselves — what each one changes, the symptom without it, and the kit commit it came from — is
`docs/KIT-FIXES.md`.) Record the claim in `.ai-dev-starter.json` as an `adopted_fixes` entry, so it
is auditable (`docs/KIT-REVISION-CONVENTION.md`; a new record carries no `files[]` — see its L3
entry). A probe whose fix lands in more than one file names each of them in its own `# guards:`
line, and the kit's runner (`tools/kit-probes.sh`) runs it once per guarded file.

A repo that took a gate from `examples/` instead of the engine keeps a `kitprobes` stage in that
gate, which runs everything in `tools/kit-probes/` against it — offline, no kit checkout, no network,
no build, under a second — and a copy with no `tools/kit-probes/` SKIPs the stage on purpose: it
means "carries no probe yet", which is not the same statement as "is behind". The seven retired gate
probes are exactly the checks such a copy wants; they are in this kit's history and
`examples/README.md` has the command that brings one back.

**Why not compare the file against the kit.** Because a copy is a *fork*, not a copy, and the
two answers a byte or diff comparison can give are both wrong here: it reports every local
decision as drift (the four real forks differ from the kit by 60, 89, 582 and 586 lines, and
nothing parses the prose that explains them), and its magnitude inverts as a signal — a copy
that is one fix behind is missing 27 kit lines while a verified, current copy is missing 125.
**Diff size measures divergence from the kit, not lateness.** A hash tells you what a repo
took and whether it adapted it on purpose; it cannot tell you what it is missing.

**What a probe cannot do** (know the limits, rather than trusting the green): it is name- and
contract-level, so a semantic regression *inside* a function that is still present is not
caught — that costs a real build and a real run; and a probe must be written per fix, so the
rule is a discipline, not a free guarantee. The kit runs its own probes with
`tools/kit-probes.sh` (`--list` shows what each one guards); run it before publishing a change
to a probe or to a template a probe guards.

---

## Step 10 — the release process (only for a repo that tags releases)

```bash
mkdir -p tools
cp "$KIT/templates/cpp/release.sh" tools/release.sh
chmod +x tools/release.sh
echo '.release/' >> .gitignore      # the notes are a draft until they are published
tools/release.sh status
```

Four commands, in this order:

```bash
tools/release.sh status             # declared version, newest tag, unreleased commits, advice
tools/release.sh prepare [--apply]  # propose the next version from the commits since the
                                    # last tag; --apply writes it to CMakeLists.txt
tools/release.sh notes [--open]     # draft .release/notes-v<version>.md, table first
tools/release.sh publish --yes      # tag + push tag + gh release create
```

The project name is read out of `CMakeLists.txt` (`project(<name> VERSION x.y.z)`), so there
is nothing to configure — a name in two places drifts, and a name in one place can be
checked. `publish` refuses unless the tree is clean, HEAD is what `origin/main` has, the tag
is absent, `gh` is present, **and the compatibility table is no longer a TODO**. That last
refusal is the point of the whole script: the mechanical parts are inferable from git, but
how an existing user's code is affected is a judgement, and a generated answer would be a
confidently wrong one.

The notes lead with that table on purpose — source → behaviour → build/package → removed,
renamed or newly required → ABI/soname — because the first question a user has about a new
version is "what happens to me". The version itself has exactly one home, the `project()`
line; if the repo has no second copy of the number yet, `templates/cpp/version.hpp.in` shows
the pair the gate's `version` stage expects, with the CMake wiring that keeps them honest.

Repos that never tag a release skip this step: a release process in a repo with no releases
is a file, not a process.

## Appendix — what each gate runs

Two gates run on this fleet now. **The engine path** is `gate.toml` + `kit-ci`: what runs is the
repo's own policy, and `kit-ci --list` prints it — there is deliberately no second list here, because
the list *is* the file. **The fallback path** is the bash gates in `examples/`; what each of those
runs is below, and it is also what a converted repo's stage scripts inherited.

**Deno** — `lint` (`deno task lint`) → `tests` (full `deno task test`) → `format`
(`deno fmt --check`, touched files only) → `artifact identity` (APP_VERSION ↔
CACHE_NAME, plus "public/ changed ⇒ version.js was bumped") → `kit probes` (step 9).

**Python** — `tools` (which ruff/pytest/mypy answered, and from where) → `lint`
(`ruff check .`) → `format` (`ruff format --check`, touched files) → `tests` (`pytest -q`;
zero collected tests is a failure) → `types` (`mypy`, only when `[tool.mypy]`/`mypy.ini`
exists) → `clean environment` → `artifact identity` → `kit probes` (step 9). The last three
depend on the branch the gate detected (it prints which one on the first line):

- **packaged** (`pyproject.toml`) — sdist + wheel built, and the **wheel installed into a
  throwaway venv**, imported there, with its console script asked for `--version`; identity =
  `pyproject.toml` version ↔ the version the installed wheel reports.
- **unpackaged** (`requirements.txt`) — a throwaway venv takes the declared requirements,
  the **suite runs from that venv** (each declared requirement's resolved version is printed,
  and a pytest missing from the list is installed for the run with a loud NOTE), plus
  `python -m <pkg> --help` when the package has a `__main__.py`; every stage runs with the
  tree's own layout on `sys.path` (`src/` or the repo root), because here the tree is the
  artifact; identity = the tracked `VERSION` file ↔ the `__version__` the code reports.

**C++** — eleven stages, run in this order in the full tier: `tree` (every file committed
or ignored; the gate's own footprint ignored; `--require-clean` fails on uncommitted
edits) → `format` (clang-format on touched files) → `kitprobes` (step 9: every probe in
`tools/kit-probes/`, against this gate script) → `build` (configure + build, and it
counts warnings even where `-Werror` is not wired on) → `tests` (ctest) → `release`
(the **second configuration**: `CI_RELEASE_BUILD_DIR` configured at
`CI_RELEASE_BUILD_TYPE` — `Release` by default — built with its own `warning:` count and
run through the same test command; every other stage builds `CI_BUILD_TYPE`, so without
this one a repo whose own pipeline builds an optimized configuration never checks one) →
`version` (CMake VERSION ↔ the generated header, optionally every binary's `--version`) →
`asan` (ASan+UBSan in a separate build dir) → `tsan` (ThreadSanitizer) → `tidy` (clang-tidy,
only NEW findings vs a baseline; capture the baseline with
`tools/ci.sh --write-tidy-baseline` rather than by hand) → `pristine` (`git archive HEAD` →
build → test).

When a stage fails the run stops there (the later stages are a chain off the build) and the
summary names every requested stage that therefore did not run:

```
  pass  tree
  FAIL  build
  stopped at: build
  BLOCK tests (did not run: the run stopped at build)
  BLOCK version (did not run: the run stopped at build)
  ...
GATE FAILED
```

Optional, and worth adding when the project has a fuzz target. Three things are worth
copying, each measured on a real target rather than reasoned about. **Give it a short smoke
run** — the proven instance gives it 10 seconds and leaves the long campaigns to a nightly
job — and know that a real fuzz stage is usually a *sequence*, not one command: Permuto's
runs a `-runs=0` seed pass that must see both identity counters move, then the timed
campaign, with the campaign length an **environment knob** (`CI_FUZZ_SECONDS`, default small)
rather than a stage key, so a manual `CI_FUZZ_SECONDS=1800 tools/ci.sh fuzz` stays possible.
**Assert the target's OUTPUT contract, not just that it does not crash:** have it render every
accepted input through every output format (or emit the verdict, the table, the baseline) and
abort on output that is empty, differs between two runs, or carries something it must not.
KitCI's parser fuzz target did exactly that and caught a real leak on its first consumer — a
repo name that spelled a URL reached the generated HTML page (commit `2b2c8da`) — before any
human rendered it. This one is guidance, not a kit fix: there is no probe, because the
contract belongs to your output, not to the gate. The stage itself goes in `CI_FULL_STAGES`
(step 2), so the pre-push hook runs it without the hook being edited.
