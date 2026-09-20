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

```bash
mkdir -p .githooks
cp "$KIT/templates/hooks/pre-commit" .githooks/pre-commit
cp "$KIT/templates/hooks/pre-push"   .githooks/pre-push
chmod +x .githooks/pre-commit .githooks/pre-push

# arm them in THIS clone (git never copies hooks for you)
git config core.hooksPath .githooks
```

These two files dispatch to whatever gate the repo has: `tools/ci.sh` if it exists (C++,
two tiers), otherwise `scripts/gate.sh` (Deno/Python, gate is already seconds). Copy
them once and they work for any language.

> **The one step nothing enforces.** A fresh clone has to run
> `git config core.hooksPath .githooks` again, and forgetting it is silent. The
> countermeasure is the clean-checkout run in step 7 (a clone that forgot the hooks still
> gets gated by the nightly job) plus a line in `CLAUDE.md`.

---

## Step 2 — the gate for this repo's language

### Deno

```bash
mkdir -p scripts
cp "$KIT/templates/deno/gate.sh" scripts/gate.sh
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

### Python

```bash
mkdir -p scripts
cp "$KIT/templates/python/gate.sh" scripts/gate.sh
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

### C++

```bash
mkdir -p tools
cp "$KIT/templates/cpp/ci.sh" tools/ci.sh
cp "$KIT/templates/cpp/.ci.env.example" .ci.env.example
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
(`build*/`) must be in `.gitignore` (step 3).

C++ is the one language with two tiers, because a full run is minutes and a commit
cannot afford minutes:

| Tier | Hook | Stages | Cost |
|---|---|---|---|
| fast | `pre-commit` | `build tests` | ~6 s on a warm build dir |
| full | `pre-push` | `--require-clean tree format kitprobes build tests release version asan tsan tidy pristine` | minutes |

---

## Step 3 — gitignore the gate's own footprint

The C++ gate's `tree` stage fails when the gate's own output would show up as untracked
files, so these must be ignored **before** the first run:

```bash
cat >> .gitignore <<'EOF'

# the gate's own footprint
.ci-logs/
build/
build-*/
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
that already exists in this repo, and set it in one of three ways:

| Language | Default the gate ships with | Change it by |
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

## Step 5 — the two documents that make the rest stick

```bash
cp "$KIT/templates/CLAUDE.md.template" CLAUDE.md   # fill in every <placeholder>
cp "$KIT/INCIDENTS.md" .                           # keep the example, add your own
```

`CLAUDE.md` must name the real commands (the gate among them) and start a **gotchas**
list. Its first entry should be the thing that has already bitten this repo — you know
what it is.

---

## Step 6 — first run: make it pass on the committed tree

```bash
scripts/gate.sh          # or: tools/ci.sh   (C++)
git status                        # nothing modified by the gate? good
```

Expect the first run to find real problems. Handle them in this order:

1. **Fix them**, if the fix is small.
2. **Record them as accepted findings**, if they are pre-existing and large — the C++
   tidy baseline exists for exactly this: run `tools/ci.sh --write-tidy-baseline` and commit
   the file it writes. (`CI_TIDY_BASELINE` in `.ci.env.example` explains why the file's form
   matters and how the comparison reads it.)
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

## Step 9 — keep your copy true to the kit: probes

Copies do not sync. A defect fixed in the kit stays live in every repo that copied that file
earlier — which is how one broken clang-tidy baseline recipe was found four separate times
before anyone noticed it was one bug. The rule that closes that class:

> **A fix that must propagate ships a probe.**

A probe is a small script in the kit's `probes/` that takes a gate script and exits non-zero
when ONE kit fix is absent from it — checked **by name and by behaviour**, not by hash and not
by diff. The reference is `probes/tidy-baseline.sh` (7 checks: the normaliser exists; it
strips the repo root and `:line:col` when fed a synthetic finding; both sides of the
comparison go through it; `--write-tidy-baseline` shares it). To carry it:

```bash
mkdir -p tools/kit-probes
cp "$KIT/probes/tidy-baseline.sh" tools/kit-probes/    # one file per fix you carry
tools/ci.sh kitprobes                                  # or: scripts/gate.sh
```

`tools/kit-probes/` **is the list of fixes your copy claims to carry**, and the `kitprobes`
stage runs every script in it against the gate that invoked it — offline, no kit checkout, no
network, no build, under a second. A copy with no `tools/kit-probes/` SKIPs the stage on
purpose: it means "carries no probe yet", which is not the same statement as "is behind".
Record each probe file in `.ai-dev-starter.json` like any other copied artifact, so the claim
is auditable (`docs/KIT-REVISION-CONVENTION.md` in the workspace that holds the kit, section
"So how drift is actually caught: probes"). A probe whose fix lands in more than one template
names each of them in its own `# guards:` line, and the kit's runner (`tools/kit-probes.sh`)
runs it once per guarded file — that is the kit's own check that all three templates satisfy
the fix, not just the one a single line could name.

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

## Appendix — what each gate runs

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

Optional, and worth adding when the project has a fuzz target: a `fuzz` stage with a
short smoke run (the proven instance gives it 10 seconds and leaves the long campaigns to
a nightly job).
