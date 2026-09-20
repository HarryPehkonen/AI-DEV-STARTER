# INCIDENTS — every real failure, and the check that now catches it

Newest first. One entry per incident that changed how this repo works.

The rule: **when something breaks, the fix is not done until a check exists that would
have caught it, and the incident is written here next to that check.** A check with no
written rationale looks arbitrary to the next hurried contributor (or agent), and
arbitrary checks get deleted. The rationale is the load-bearing part.

    ## YYYY-MM-DD — <one-line failure>
    What broke:        <the user-visible symptom>
    Check added:       <file> + <gate stage that now catches it>
    Why it must stay:  <why deleting this check re-enables the bug>

---

## 2026-09-20 — the python gate's tests stage could not import a src-layout tree

What broke:        An unpackaged repo (`requirements.txt`, no `pyproject.toml`) with the
                   package under `src/` failed the python gate's `tests` stage with
                   `ModuleNotFoundError: No module named '<pkg>'` — while the same suite
                   passed two stages later in the throwaway venv. The tools ran bare:
                   pytest's rootdir insertion reaches only the tests directory, and
                   `python -m pytest` puts only the repo root on `sys.path`, so a package
                   under `src/` was invisible to the suite. A flat layout hides it (the
                   package sits on the repo root, which `python -m` already has on
                   `sys.path`), which is why docsum — flat — never showed it. The shape is
                   the worst one for a gate: red on a repo whose suite is green, i.e. "the
                   gate is wrong", which is how gates get muted.
Check added:       `templates/python/gate.sh`: `tool_env` wraps every tool invocation and, on
                   the unpackaged branch only, runs it through `py_env` — the tools see
                   exactly the `sys.path` the tree declares (`src/` for a src layout, nothing
                   extra for a flat one) and never a `PYTHONPATH` the caller exported. The
                   packaged branch is deliberately untouched: there the environment being
                   asked about is the one the wheel installed.
Why it must stay:  Without it the unpackaged branch supports only one of the two layouts it
                   claims to, and the failure is indistinguishable from a broken suite — the
                   clean-environment stage proves the code is fine while the tests stage says
                   it is not. The tempting fix (a `conftest.py` `sys.path` shim in the repo)
                   moves the gate's layout knowledge into every repo that copies the gate.

---

## 2026-09-20 — the documented tidy baseline made the tidy stage permanently red

What broke:        Following the kit's own comment in `templates/cpp/.ci.env.example`, a repo
                   with inherited clang-tidy findings (Computo) captured a baseline with
                   `tools/ci.sh tidy && grep -E "warning:|error:" .ci-logs/tidy.log | sort -u`
                   `> .ci/tidy-baseline.txt`. The tidy stage normalises the log side before
                   comparing, so nothing in a raw baseline ever matched: `new_findings` came
                   out equal to the total and the stage failed on every finding the file was
                   supposed to tolerate. Three more holes sat on the same line — `.ci/` did
                   not exist (the redirect failed), the `build` stage had to have run first or
                   tidy hard-fails with no compile database, and the `&&` meant the failing
                   tidy wrote no baseline at all. Two more were inside the comparison: the
                   baseline side was de-duplicated while the log side was not (a file holding
                   two identical findings reported one as "new" even with a correct baseline),
                   and clang-tidy prints the ABSOLUTE path from the compile database, so a
                   baseline captured in one clone described nothing in a checkout at another
                   path — the nightly clean-checkout caller was red for a second reason.
Check added:       `templates/cpp/ci.sh`: the normalisation is one function, `tidy_key`
                   (repo-root prefix and `:line:column` removed, one key per finding), applied
                   to BOTH operands and de-duplicated on both sides; and
                   `tools/ci.sh --write-tidy-baseline` captures the baseline through that same
                   function — running the build and tidy stages itself, then printing the
                   `git add` line, because a baseline that is neither committed nor ignored
                   fails the tree stage.
Why it must stay:  Without the shared normalisation the documented path is a permanently red
                   stage, and a stage nobody can turn green gets bypassed — the failure this
                   kit exists to remove. Without stripping the paths, the same red state comes
                   back in every clone and on the nightly job. The lesson generalises past
                   clang-tidy: a capture recipe written by hand into a comment is a second
                   implementation of the comparison, and the two drift.

---

## 2026-09-19 — the version stage passed while checking nothing

What broke:        Wired into a real repo (Computo) with `CI_VERSION_BINARIES="$CI_BUILD_DIR/computo"`
                   exactly as the kit documents it, the version stage printed
                   `0 binary/binaries report 1.0.0` and PASSED. `CI_TEST_CMD` is fed to
                   `eval`; `CI_VERSION_BINARIES` was word-split only, so the literal
                   `$CI_BUILD_DIR/...` matched no file, every candidate was skipped, and
                   a stage whose entire job is "the artifacts must agree" certified
                   nothing. A gate that fails open is the one shape this kit exists to
                   remove.
Check added:       `templates/cpp/ci.sh` stage_version: the list is expanded with `eval`
                   like CI_TEST_CMD, and zero matching executables is now a FAIL
                   ("matched no executable — the binaries were NOT checked").
Why it must stay:  Without the eval, following the kit's own documentation silently
                   disables the check; without the zero-match failure, any typo, wrong
                   build-dir name or unbuilt binary turns the stage into a rubber stamp
                   that still prints green.

---

## 2026-09-19 — a repo's own defaults were silently ignored

What broke:        Narrowing the gate for a real repo meant adding the repo's own defaults
                   below the kit's in `tools/ci.sh`. Written as `CI_TEST_CMD=${CI_TEST_CMD:-...}`
                   the new value was ignored: the kit's line above it had already set the
                   variable, so `${VAR:-default}` kept the OLD value. The gate ran the
                   un-narrowed command for a whole run and the "narrowing" was decorative —
                   the summary looked like the intended gate, and the excluded tests
                   simply ran anyway.
Check added:       Both wired repos (Computo, Permuto) assert it in the script itself:
                   the repo block assigns the values directly and says why, and
                   `tools/ci.sh --list` prints the effective `CI_DEFAULT_STAGES`. Compare
                   that line with the adaptation notes before trusting a narrowed gate.
Why it must stay:  This is the quietest way to lose a gate: nothing errors, nothing
                   warns, the stage list is close enough to look right, and the one command
                   that shows the difference (`--list`) is the one nobody runs.

---

## 2026-09-19 — tests that cannot pass under a sanitizer

What broke:        The first ASan+UBSan run of a real repo failed 3 of 3 suites, none of
                   it the sanitizers' doing: two cases measure the process's RSS growth
                   before/after a test to detect a leak ("Potential memory leak detected:
                   179064 KB memory increase") and a sanitizer keeps freed memory in its
                   quarantine; two more are wall-clock benchmarks
                   (`EXPECT_GT(ops_per_second, 10000.0)`) that a sanitized build is
                   deliberately too slow to pass. The gate was red at HEAD, on an
                   untouched tree.
Check added:       `templates/cpp/ci.sh` stage_asan honours an optional
                   `CI_ASAN_TEST_CMD` (defaults to CI_TEST_CMD), and the wired repos set
                   it with `GTEST_FILTER=-<the sanitizer-incompatible cases>`, so one
                   ctest run covers every suite and still drops only those cases.
Why it must stay:  Without a per-stage command the choice is "no sanitizer stage" or "a
                   permanently red one", and a permanently red gate is a bypassed gate.
                   The excluded names are listed with their measured numbers in each
                   repo's `.ci.env.example`, which is also the list to delete from when
                   the tests are made sanitizer-aware.

---

## 2026-09-18 — a new file's formatting was never checked (example entry)

What broke:        A source file written and committed during a working session failed
                   the format gate the next morning — the drift had been in the commit
                   the whole time. `git diff` cannot see a file that is untracked, so the
                   format stage looked at an empty file list for exactly the files that
                   were newest, and passed.
Check added:       `scripts/gate.sh` format stage (deno) / `tools/ci.sh` format stage (C++):
                   the touched-file list is built from `git diff` PLUS
                   `git ls-files --others --exclude-standard`, so a brand-new file is
                   checked the moment it exists, not after it is committed.
Why it must stay:  Removing the `git ls-files --others` line makes the gate blind to
                   exactly the files a contributor just wrote — the ones most likely to be
                   wrong. It passed on the old list, so nothing else will notice.

---

<!--
Copy this file into a repo root as INCIDENTS.md and keep this example as the shape
reference (or delete it once you have two real entries). Then, forever after: the commit
that fixes a failure also adds its entry here and the check that catches it.
-->
