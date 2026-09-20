#!/usr/bin/env bash
#
# Local CI — every gate this repo has, in one script, with no service anywhere.
#
# from AI-DEV-STARTER (plunk-in kit) — if you edit this file, say why in INCIDENTS.md.
#
# No GitHub, no network, no framework: this is what the git hooks in .githooks/ run,
# and you can run it by hand at any time (it is non-destructive — nothing is committed,
# staged, reverted or reformatted for you).
#
#   tools/ci.sh                      # all default stages, in order
#   tools/ci.sh build tests          # just these stages, in the order given
#   tools/ci.sh --list               # what the stages are
#   tools/ci.sh --write-tidy-baseline   # accept the tidy findings you inherited
#   tools/ci.sh --help
#
#   git config core.hooksPath .githooks     # one-time, per clone, enables the hooks
#
# Two tiers, because a C++ full run is minutes and a commit cannot afford minutes:
#
#   fast  (pre-commit)  build tests
#   full  (pre-push)    --require-clean tree format build tests version asan tsan tidy pristine
#
# Configuration lives in .ci.env (gitignored, optional); every knob has a default here,
# so the repo works with no config at all. See .ci.env.example.
#
# Exit status: 0 only if every stage that ran passed.
#
# One deliberate reading of "report every failure": a failing stage prints EVERYTHING
# that failed inside it (every unformatted file, every failing test, every finding) and
# then STOPS the run, because these stages are a chain — once the build fails, the
# tests, sanitizers and pristine stages would only repeat the same compiler error with
# more noise. Stages that do not depend on each other (tree, format, version) are
# cheap and run first for that reason. Where a run stops, the summary says so.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT" || exit 1

# No colour from the tools: this script greps their output (warning:, error:) and ANSI
# escapes defeat the greps. The escapes this script prints itself are for the human.
export NO_COLOR=1

# ---------------------------------------------------------------- defaults + config
CI_JOBS=${CI_JOBS:-$(nproc 2>/dev/null || echo 4)}
CI_BUILD_DIR=${CI_BUILD_DIR:-build}
CI_ASAN_BUILD_DIR=${CI_ASAN_BUILD_DIR:-build-asan}
CI_TSAN_BUILD_DIR=${CI_TSAN_BUILD_DIR:-build-tsan}
CI_LOG_DIR=${CI_LOG_DIR:-.ci-logs}
CI_STRICT_TOOLS=${CI_STRICT_TOOLS:-0}           # 1 = a missing tool fails instead of SKIPping
CI_KEEP_TMP=${CI_KEEP_TMP:-0}                   # 1 = keep the pristine temp dir for inspection
CI_DEFAULT_STAGES=${CI_DEFAULT_STAGES:-"tree format build tests version asan tsan tidy pristine"}
CI_TIDY_BASELINE=${CI_TIDY_BASELINE:-.ci/tidy-baseline.txt}
CI_BUILD_TYPE=${CI_BUILD_TYPE:-Debug}
# The source set the format and tidy stages own. Extend for your layout.
CI_SOURCE_GLOBS=${CI_SOURCE_GLOBS:-"'*.cpp' '*.cc' '*.cxx' '*.hpp' '*.hh' '*.h'"}
# Where the SECOND copy of the version number lives. Two forms are both fine:
#   the CMake-generated header  (configure_file(version.hpp.in ...) -> ${CMAKE_BINARY_DIR}/generated/version.hpp)
#   a tracked header            (include/<project>/version.hpp) — point this knob at it
CI_VERSION_HEADER=${CI_VERSION_HEADER:-"$CI_BUILD_DIR/generated/version.hpp"}
# The test runner. ctest is the portable default; override with a single test binary if
# your project does not register tests with add_test().
CI_TEST_CMD=${CI_TEST_CMD:-"ctest --test-dir \$CI_BUILD_DIR --output-on-failure -j \$CI_JOBS"}

if [ -f .ci.env ]; then
    # shellcheck disable=SC1091
    . ./.ci.env
fi

REQUIRE_CLEAN=0
ALLOW_UNTRACKED=0
WRITE_TIDY_BASELINE=0
STAGES_REQUESTED=()

# ---------------------------------------------------------------- plumbing
RESULT_LINES=()
FAILED_STAGE=""
RAN_STAGES=()
RUN_TMP_DIRS=()

usage() {
    # The whole leading comment block: every line from 2 to the first blank one. Derived
    # rather than hard-coded, so adding a line to the header cannot silently cut it off.
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Stages:
  tree        every file committed or ignored; .gitignore audit; the gate's own
              footprint (build dirs, logs, .ci.env) is ignored; --require-clean also
              fails on uncommitted changes to tracked files
  format      clang-format drift — dry run against the repo .clang-format
  build       cmake configure + build, zero warnings (the stage counts them even where
              -Werror is not wired onto a target)
  tests       the test suite (ctest by default), every failure reported
  version     one version number: project(VERSION) in CMakeLists.txt == the header the
              build generates/uses, and the number every binary prints for --version
  asan        separate build dir, ASan+UBSan, same suite
  tsan        separate build dir, ThreadSanitizer, same suite
  tidy        clang-tidy, only NEW findings vs CI_TIDY_BASELINE (a baseline file is
              optional; with none, tidy must be clean). Findings compare line-blind and
              clone-blind — capture the baseline with --write-tidy-baseline, never by
              hand (a raw copy of the log matches nothing: see .ci.env.example)
  pristine    git archive HEAD -> temp dir -> configure, build, test: proves the
              COMMITTED tree is complete (catches files that are uncommitted or ignored)

Options:
  --require-clean     make the tree stage fail when tracked files have uncommitted edits
  --allow-untracked   do not fail when untracked, unignored files exist (deliberate escape)
  --strict-tools      a missing tool (clang-format/clang-tidy) fails instead of skipping
  --write-tidy-baseline
                      accept every finding tidy reports now into CI_TIDY_BASELINE (runs the
                      build and tidy stages first); prints, and IS NOT, a gate pass
  --list              list the stages and exit
  --help              this text
EOF
}

ci_begin() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ci_pass() { RESULT_LINES+=("pass  $1"); }
ci_skip() {
    RESULT_LINES+=("SKIP  $1 ($2)")
    printf '    SKIP: %s\n' "$2"
}

ci_fail() {
    local name="$1" reason="$2" logfile="${3:-}"
    RESULT_LINES+=("FAIL  $name")
    printf '\n\033[1;31mFAILED: %s — %s\033[0m\n' "$name" "$reason"
    if [ -n "$logfile" ] && [ -f "$logfile" ]; then
        printf '    last output from %s:\n' "$logfile"
        tail -n 25 "$logfile" | sed 's/^/      /'
        printf '    full log: %s\n' "$logfile"
    fi
    FAILED_STAGE="$name"
    summary
    printf '\nGATE FAILED\n' >&2
    exit 1
}

summary() {
    printf '\n--- ci summary ---\n'
    local line
    for line in "${RESULT_LINES[@]}"; do printf '  %s\n' "$line"; done
    if [ -n "$FAILED_STAGE" ]; then
        printf '  stopped at: %s\n' "$FAILED_STAGE"
        # A stage that never ran because an earlier one failed must not look like a
        # stage that passed. Naming it is the whole difference between "everything is
        # fine" and "the tests never ran" — this is why the run stops instead of
        # pretending: once the build fails, the test stage has nothing trustworthy to
        # say, so it is reported as blocked, never as green.
        local s r ran
        for s in "${STAGES_REQUESTED[@]:-}"; do
            [ -n "$s" ] || continue
            ran=0
            for r in "${RAN_STAGES[@]:-}"; do
                [ "$r" = "$s" ] && ran=1
            done
            if [ "$ran" = "0" ] && [ "$s" != "$FAILED_STAGE" ]; then
                printf '  BLOCK %s (did not run: the run stopped at %s)\n' "$s" "$FAILED_STAGE"
            fi
        done
    fi
}

require_tool() {  # require_tool <tool> <stage>; returns 1 when the caller should skip
    local tool="$1" stage="$2"
    if command -v "$tool" >/dev/null 2>&1; then return 0; fi
    if [ "$CI_STRICT_TOOLS" = "1" ]; then
        ci_fail "$stage" "$tool not installed (CI_STRICT_TOOLS=1) — nothing was checked"
    fi
    ci_skip "$stage" "$tool not installed — this gate was NOT exercised on this machine"
    return 1
}

# The file set the format gate owns: same list the CMake `format` target should use.
# --others --exclude-standard includes new files that are not committed yet: while
# working, a new source file is not in `git ls-files`, and a gate that cannot see it
# lets it through unformatted until after it is committed (that incident is in
# INCIDENTS.md).
ci_sources() {
    # shellcheck disable=SC2086
    eval "git ls-files --cached --others --exclude-standard -- $CI_SOURCE_GLOBS" | sort -u
}

# clang-tidy needs a compile database entry per translation unit, so headers are not
# passed here: diagnostics inside headers still surface through the sources that include
# them (that is what .clang-tidy's HeaderFilterRegex is for).
ci_tidy_sources() {
    # shellcheck disable=SC2086
    eval "git ls-files --cached --others --exclude-standard -- $CI_SOURCE_GLOBS" \
        | grep -E '\.(cpp|cc|cxx)$' | sort -u
}

# The comparable form of a clang-tidy finding — applied to BOTH sides of the baseline
# comparison, so the file a repo captures and the log this gate just wrote are the same
# shape:
#
#   <repo>/src/foo.cpp:42:7: warning: ...   ->   src/foo.cpp: warning: ...
#
#   * the repo root is stripped: clang-tidy reports the path it was handed by the compile
#     database, which CMake writes as an absolute path, so a baseline captured in one clone
#     names no finding in a checkout at another path (the nightly clean checkout, a
#     colleague's machine) and every inherited finding reads as new;
#   * :line:column is stripped, so the same finding after an unrelated edit above it is
#     still the same finding. This is line-blind on purpose, and the flip side is worth
#     knowing: a SECOND identical finding in a file that already has one collapses into the
#     first. Fix the baselined finding instead of growing the baseline.
#
# `tools/ci.sh --write-tidy-baseline` captures the baseline through this same function, so
# the documented way to accept findings cannot drift from the way they are compared.
tidy_key() {
    awk -v root="$REPO_ROOT/" '
        { i = index($0, root); if (i) $0 = substr($0, i + length(root)); print }' \
        | sed 's/:[0-9]*:[0-9]*:/:/'
}

run_tests() {  # run_tests <build-dir> <logfile>
    # shellcheck disable=SC2086
    eval "$CI_TEST_CMD" > "$2" 2>&1
}

mkdir -p "$CI_LOG_DIR"

# ---------------------------------------------------------------- stages
stage_tree() {
    ci_begin "tree (every file committed or ignored)"
    # The gate creates these; a .gitignore that does not cover them makes the next run
    # fail the moment it writes a log. Create them first: git check-ignore cannot match
    # a directory pattern against a path that does not exist yet.
    mkdir -p "$CI_BUILD_DIR" "$CI_ASAN_BUILD_DIR" "$CI_TSAN_BUILD_DIR" "$CI_LOG_DIR"

    local untracked
    untracked=$(git ls-files --others --exclude-standard)
    if [ -n "$untracked" ]; then
        printf '    not committed and not ignored:\n'
        printf '%s\n' "$untracked" | sed 's/^/      /'
        if [ "$ALLOW_UNTRACKED" = "1" ]; then
            printf '    (not failing: --allow-untracked was passed)\n'
        else
            ci_fail tree "$(printf '%s\n' "$untracked" | wc -l) file(s) are neither committed nor ignored — git add them, or add a .gitignore rule"
        fi
    else
        printf '    no untracked, unignored files\n'
    fi

    local dirty
    dirty=$(git status --porcelain --untracked-files=no)
    if [ -n "$dirty" ]; then
        printf '    uncommitted changes to tracked files:\n'
        printf '%s\n' "$dirty" | sed 's/^/      /'
        if [ "$REQUIRE_CLEAN" = "1" ]; then
            ci_fail tree "uncommitted changes to tracked files (that is the point of the push gate)"
        fi
        printf '    (not failing: --require-clean was not passed)\n'
    else
        printf '    no uncommitted changes to tracked files\n'
    fi

    local tracked_ignored
    tracked_ignored=$(git ls-files -i -c --exclude-standard)
    if [ -n "$tracked_ignored" ]; then
        printf '%s\n' "$tracked_ignored" > "$CI_LOG_DIR/tree.log"
        ci_fail tree "tracked files matched by .gitignore (stale rules) — see $CI_LOG_DIR/tree.log"
    fi

    local path missing=0
    for path in "$CI_BUILD_DIR" "$CI_ASAN_BUILD_DIR" "$CI_TSAN_BUILD_DIR" "$CI_LOG_DIR" ".ci.env"; do
        if ! git check-ignore -q "$path" 2>/dev/null; then
            printf '    NOT ignored: %s\n' "$path"
            missing=$((missing + 1))
        fi
    done
    if [ "$missing" -gt 0 ]; then
        ci_fail tree "$missing path(s) that the gate itself creates are not in .gitignore — the next run would fail on its own log files"
    fi
    printf '    gate footprint (build dirs, %s, .ci.env) is ignored\n' "$CI_LOG_DIR"
    ci_pass tree
}

stage_format() {
    ci_begin "format (clang-format --dry-run) — the files this branch touches"
    require_tool clang-format format || return 0
    # Only the files this branch touches: the repo has pre-existing non-compliant files
    # and a whole-tree check buries the signal in noise nobody edited. On a clean
    # checkout (nothing ahead of origin/main) fall back to the last commit.
    local base touched
    base="$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse HEAD)"
    touched="$(
        { git diff --name-only --diff-filter=ACMR "$base" HEAD
          git diff --name-only --diff-filter=ACMR HEAD
          git ls-files --others --exclude-standard
        } | sort -u
    )"
    if [ -z "$touched" ]; then
        touched="$(git show --name-only --pretty=format: HEAD | sed '/^$/d')"
        printf '    (level with origin/main: checking the last commit instead)\n'
    fi
    local -a sources
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && sources+=("$f")
    done < <(printf '%s\n' "$touched" | grep -E '\.(cpp|cc|cxx|hpp|hh|h)$')
    if [ "${#sources[@]}" -eq 0 ]; then
        printf '    nothing to check\n'
        ci_pass format
        return 0
    fi
    if clang-format --dry-run -Werror "${sources[@]}" > "$CI_LOG_DIR/format.log" 2>&1; then
        printf '    %s file(s) conform to .clang-format\n' "${#sources[@]}"
        ci_pass format
        return 0
    fi
    grep -oE '^[^:]+\.(cpp|cc|cxx|hpp|hh|h)' "$CI_LOG_DIR/format.log" | sort -u | sed 's/^/      /'
    ci_fail format "clang-format drift in the files listed above (fix: clang-format -i <those files>)" "$CI_LOG_DIR/format.log"
}

stage_build() {
    ci_begin "build (-Werror, zero warnings)"
    # shellcheck disable=SC2086
    cmake -S . -B "$CI_BUILD_DIR" -DCMAKE_BUILD_TYPE="$CI_BUILD_TYPE" \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ${CI_CMAKE_FLAGS:-} > "$CI_LOG_DIR/configure.log" 2>&1 \
        || ci_fail build "cmake configure failed" "$CI_LOG_DIR/configure.log"
    cmake --build "$CI_BUILD_DIR" -j "$CI_JOBS" > "$CI_LOG_DIR/build.log" 2>&1 \
        || ci_fail build "build failed (-Werror is on: a warning is a build failure)" "$CI_LOG_DIR/build.log"
    # -Werror only covers the targets it is wired onto, so a target that never got the
    # flag would build with warnings and pass. Count them here too.
    local warns
    warns=$(grep -c 'warning:' "$CI_LOG_DIR/build.log" || true)
    if [ "${warns:-0}" -gt 0 ]; then
        grep 'warning:' "$CI_LOG_DIR/build.log" | head -5 | sed 's/^/      /'
        ci_fail build "$warns compiler warning(s) in a target -Werror does not cover" "$CI_LOG_DIR/build.log"
    fi
    printf '    built with no warnings\n'
    ci_pass build
}

stage_tests() {
    ci_begin "tests"
    if [ ! -f "$CI_BUILD_DIR/CMakeCache.txt" ]; then
        ci_fail tests "no build configured in $CI_BUILD_DIR — run the build stage first"
    fi
    if ! run_tests "$CI_BUILD_DIR" "$CI_LOG_DIR/tests.log"; then
        grep -E "FAILED|Failed|\*\*\*Failed|assert" "$CI_LOG_DIR/tests.log" | head -30 | sed 's/^/      /'
        ci_fail tests "test failures (all of them are above; full output in the log)" "$CI_LOG_DIR/tests.log"
    fi
    grep -E "tests passed|100% tests passed" "$CI_LOG_DIR/tests.log" | tail -1 | sed 's/^/      /'
    ci_pass tests
}

stage_version() {
    ci_begin "version (two copies of one number must agree)"
    local cmake_version
    cmake_version=$(sed -n 's/^project *( *[A-Za-z0-9_.-]* *VERSION *\([0-9][0-9.]*\).*/\1/p' CMakeLists.txt | head -1)
    if [ -z "$cmake_version" ]; then
        ci_fail version "could not read a VERSION from CMakeLists.txt — project(<name> VERSION <x.y.z>) is what this stage parses"
    fi

    local header="$CI_VERSION_HEADER"
    if [ ! -f "$header" ]; then
        # Help, not guesswork: say which files could hold the second copy.
        local candidates
        candidates=$(find "$CI_BUILD_DIR" -type f \( -name '*version*.hpp' -o -name '*version*.h' \) 2>/dev/null | sort | head -5)
        if [ -n "$candidates" ]; then
            printf '    %s not found. Version-named headers in %s:\n' "$header" "$CI_BUILD_DIR"
            printf '%s\n' "$candidates" | sed 's/^/      /'
        fi
        ci_fail version "the header holding the second copy of the number is not at $CI_VERSION_HEADER — point CI_VERSION_HEADER at it (a tracked header works too)"
    fi
    local header_version
    # Any of:  #define APP_VERSION "1.2.3"   |   static constexpr char VERSION[] = "1.2.3";
    header_version=$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+[^"]*"' "$header" | head -1 | tr -d '"')
    if [ -z "$header_version" ]; then
        ci_fail version "$header holds no quoted x.y.z version string"
    fi
    if [ "$cmake_version" != "$header_version" ]; then
        printf '    CMakeLists.txt says %s, %s says %s\n' "$cmake_version" "$header" "$header_version"
        ci_fail version "the two copies of the version number disagree (bump both from the same edit)"
    fi
    printf '    %s == %s == %s\n' "CMakeLists.txt" "$header" "$cmake_version"

    # And, optionally, the binaries have to report it: a version nobody can ask for is
    # not a version. Off by default because every project names its executables
    # differently — set CI_VERSION_BINARIES="$CI_BUILD_DIR/myapp*" in .ci.env when the
    # naming is stable (see .ci.env.example).
    if [ -n "${CI_VERSION_BINARIES:-}" ]; then
        local binary reported checked=0 wrong=0
        # eval, exactly like CI_TEST_CMD: the documented value is "$CI_BUILD_DIR/myapp",
        # and a plain word-split would carry that through as an unexpanded literal, match
        # no file, and then print "0 binary/binaries report <version>" -- a PASS. That is
        # the fails-open shape this script exists to prevent, so the miss is also a FAIL
        # below.
        local binary_list
        eval "binary_list=\"$CI_VERSION_BINARIES\""
        for binary in $binary_list; do
            [ -f "$binary" ] && [ -x "$binary" ] || continue
            reported=$("$binary" --version 2>&1 | head -1)
            case "$reported" in
                *"$cmake_version"*) checked=$((checked + 1)) ;;
                *) wrong=$((wrong + 1)); printf '      %s --version printed: %s\n' "$(basename "$binary")" "$reported" ;;
            esac
        done
        if [ "$wrong" -gt 0 ]; then
            ci_fail version "$wrong binary/binaries do not report a --version containing $cmake_version"
        fi
        if [ "$checked" -eq 0 ]; then
            ci_fail version "CI_VERSION_BINARIES=\"$CI_VERSION_BINARIES\" matched no executable — the binaries were NOT checked"
        fi
        printf '    %s binary/binaries report %s\n' "$checked" "$cmake_version"
    else
        printf '    (CI_VERSION_BINARIES unset: the binaries were not asked for --version)\n'
    fi
    ci_pass version
}

stage_asan() {
    ci_begin "asan (ASan+UBSan, separate build dir)"
    # shellcheck disable=SC2086
    cmake -S . -B "$CI_ASAN_BUILD_DIR" -DCMAKE_BUILD_TYPE=Debug \
        -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g" \
        ${CI_CMAKE_FLAGS:-} > "$CI_LOG_DIR/asan-configure.log" 2>&1 \
        || ci_fail asan "cmake configure failed" "$CI_LOG_DIR/asan-configure.log"
    cmake --build "$CI_ASAN_BUILD_DIR" -j "$CI_JOBS" > "$CI_LOG_DIR/asan-build.log" 2>&1 \
        || ci_fail asan "sanitizer build failed" "$CI_LOG_DIR/asan-build.log"
    # CI_ASAN_TEST_CMD: optional, for tests that cannot run under sanitizers at all
    # (RSS-based leak heuristics, wall-clock benchmarks). Defaults to CI_TEST_CMD, so
    # without it the sanitizer run is the same command in a different build dir.
    local saved="$CI_TEST_CMD"
    # shellcheck disable=SC2086
    CI_TEST_CMD="$(printf '%s' "${CI_ASAN_TEST_CMD:-$CI_TEST_CMD}" | sed "s|\$CI_BUILD_DIR|$CI_ASAN_BUILD_DIR|g")"
    if ! UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1 ASAN_OPTIONS=detect_leaks=1 \
        run_tests "$CI_ASAN_BUILD_DIR" "$CI_LOG_DIR/asan-tests.log"; then
        grep -E "ERROR: AddressSanitizer|runtime error|FAILED" "$CI_LOG_DIR/asan-tests.log" | head -20 | sed 's/^/      /'
        ci_fail asan "ASan/UBSan reported something" "$CI_LOG_DIR/asan-tests.log"
    fi
    CI_TEST_CMD="$saved"
    printf '    clean under ASan+UBSan\n'
    ci_pass asan
}

stage_tsan() {
    ci_begin "tsan (ThreadSanitizer, separate build dir)"
    # A thread sanitizer on a single-threaded suite still catches static/shared state
    # touched from more than one thread — the bug this gate exists for.
    # shellcheck disable=SC2086
    cmake -S . -B "$CI_TSAN_BUILD_DIR" -DCMAKE_BUILD_TYPE=Debug \
        -DCMAKE_CXX_FLAGS="-fsanitize=thread -fno-omit-frame-pointer -g" \
        ${CI_CMAKE_FLAGS:-} > "$CI_LOG_DIR/tsan-configure.log" 2>&1 \
        || ci_fail tsan "cmake configure failed" "$CI_LOG_DIR/tsan-configure.log"
    cmake --build "$CI_TSAN_BUILD_DIR" -j "$CI_JOBS" > "$CI_LOG_DIR/tsan-build.log" 2>&1 \
        || ci_fail tsan "ThreadSanitizer build failed" "$CI_LOG_DIR/tsan-build.log"
    local saved="$CI_TEST_CMD"
    CI_TEST_CMD="$(printf '%s' "$saved" | sed "s|\$CI_BUILD_DIR|$CI_TSAN_BUILD_DIR|g")"
    if ! TSAN_OPTIONS=halt_on_error=1 run_tests "$CI_TSAN_BUILD_DIR" "$CI_LOG_DIR/tsan.log"; then
        grep -E "WARNING: ThreadSanitizer|data race|FAILED" "$CI_LOG_DIR/tsan.log" | head -20 | sed 's/^/      /'
        ci_fail tsan "ThreadSanitizer reported a data race (or a wrong answer)" "$CI_LOG_DIR/tsan.log"
    fi
    CI_TEST_CMD="$saved"
    printf '    no data races reported\n'
    ci_pass tsan
}

stage_tidy() {
    ci_begin "tidy (clang-tidy, only NEW findings)"
    require_tool clang-tidy tidy || return 0
    if [ ! -f "$CI_BUILD_DIR/compile_commands.json" ]; then
        ci_fail tidy "no $CI_BUILD_DIR/compile_commands.json — configure with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON (the build stage does) before tidy can say anything"
    fi
    local -a sources
    mapfile -t sources < <(ci_tidy_sources)
    if [ "${#sources[@]}" -eq 0 ]; then
        ci_fail tidy "no sources matched $CI_SOURCE_GLOBS — tidy would analyse nothing and still pass"
    fi

    # A compile database that exists is not a compile database that covers this repo:
    # CMake can write one that holds a dependency's translation units and none of ours.
    # clang-tidy then analyses nothing, finds no header, and still prints a result.
    local uncovered=0 src
    for src in "${sources[@]}"; do
        if ! grep -qF "\"$REPO_ROOT/$src\"" "$CI_BUILD_DIR/compile_commands.json"; then
            printf '    not in the compile database: %s\n' "$src"
            uncovered=$((uncovered + 1))
        fi
    done
    if [ "$uncovered" -gt 0 ]; then
        ci_fail tidy "$uncovered of ${#sources[@]} sources are missing from $CI_BUILD_DIR/compile_commands.json — the result would be a lie"
    fi
    printf '    compile database covers all %s sources\n' "${#sources[@]}"

    printf '%s\n' "${sources[@]}" \
        | xargs -P "$CI_JOBS" -n 1 clang-tidy -p "$CI_BUILD_DIR" > "$CI_LOG_DIR/tidy.log" 2>&1
    local findings
    findings=$(grep -cE 'warning:|error:' "$CI_LOG_DIR/tidy.log" || true)
    if [ "${findings:-0}" -gt 0 ] && [ -f "$CI_TIDY_BASELINE" ]; then
        local new_findings
        # Both sides go through tidy_key, and both sides are de-duplicated: one key per
        # distinct finding. A baseline captured by `--write-tidy-baseline` is already in
        # that form; anything else in the file is normalised here rather than trusted.
        new_findings=$(comm -13 \
            <(tidy_key < "$CI_TIDY_BASELINE" | sort -u) \
            <(grep -E "warning:|error:" "$CI_LOG_DIR/tidy.log" | tidy_key | sort -u) | wc -l)
        if [ "$new_findings" -gt 0 ]; then
            ci_fail tidy "$new_findings new finding(s) vs $CI_TIDY_BASELINE" "$CI_LOG_DIR/tidy.log"
        fi
        printf '    no new findings vs %s (%s total)\n' "$CI_TIDY_BASELINE" "$findings"
    elif [ "${findings:-0}" -gt 0 ]; then
        grep -E 'warning:|error:' "$CI_LOG_DIR/tidy.log" | sed 's/^/      /' | head -20
        ci_fail tidy "$findings finding(s) and no baseline file — accept them in one step with 'tools/ci.sh --write-tidy-baseline', or fix them; see .ci.env.example" "$CI_LOG_DIR/tidy.log"
    else
        printf '    %s files clean\n' "${#sources[@]}"
    fi
    ci_pass tidy
}

# Capture the accepted-findings baseline. Not a stage: the list is compared against every
# finding in the log, not against the outcome of the run, and the run is EXPECTED to fail
# while there is no baseline yet. It runs the real stages as a child so there is exactly one
# definition of what a finding is (tidy_key) and of where tidy's log comes from.
write_tidy_baseline() {
    printf '\n\033[1m==> write the tidy baseline\033[0m (%s)\n' "$CI_TIDY_BASELINE"
    printf '    running the real build + tidy stages (build first: tidy refuses to run without\n'
    printf '    %s/compile_commands.json; treat the tidy failure below as expected)\n\n' "$CI_BUILD_DIR"
    bash "$0" build tidy > "$CI_LOG_DIR/write-baseline.log" 2>&1
    if [ ! -f "$CI_LOG_DIR/tidy.log" ]; then
        printf 'no %s was written, so there is nothing to capture — the run stopped before the tidy stage:\n' "$CI_LOG_DIR/tidy.log" >&2
        tail -n 20 "$CI_LOG_DIR/write-baseline.log" | sed 's/^/      /' >&2
        printf '    full log: %s\n' "$CI_LOG_DIR/write-baseline.log" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$CI_TIDY_BASELINE")"
    grep -E 'warning:|error:' "$CI_LOG_DIR/tidy.log" | tidy_key | sort -u > "$CI_TIDY_BASELINE"
    local accepted
    accepted=$(grep -c . "$CI_TIDY_BASELINE" || true)
    printf '    %s finding(s) accepted into %s:\n' "${accepted:-0}" "$CI_TIDY_BASELINE"
    head -20 "$CI_TIDY_BASELINE" | sed 's/^/      /'
    if [ "${accepted:-0}" -eq 0 ]; then
        printf '\nNothing to accept: the tidy stage is clean, so delete %s and keep the stage strict.\n' "$CI_TIDY_BASELINE"
        exit 0
    fi
    printf '\nThis is NOT a gate pass: from now on the tidy stage tolerates exactly these findings\n'
    printf 'and fails on anything else. Commit the file — it is this repo'"'"'s accepted-findings list,\n'
    printf 'and the tree stage fails on a file that is neither committed nor ignored:\n'
    printf '    git add %s && git commit -m "ci: accept the inherited clang-tidy findings"\n' "$CI_TIDY_BASELINE"
}

stage_pristine() {
    ci_begin "pristine (does the COMMITTED tree build on its own?)"
    local tmp
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/ci-pristine-XXXXXX")
    RUN_TMP_DIRS+=("$tmp")
    git archive HEAD | tar -x -C "$tmp" || ci_fail pristine "git archive HEAD failed"
    printf '    HEAD checked out: %s files\n' "$(find "$tmp" -type f | wc -l)"

    # shellcheck disable=SC2086
    cmake -S "$tmp" -B "$tmp/build" -DCMAKE_BUILD_TYPE="$CI_BUILD_TYPE" \
        ${CI_CMAKE_FLAGS:-} > "$CI_LOG_DIR/pristine-configure.log" 2>&1 \
        || ci_fail pristine "a fresh checkout of HEAD does not even configure (a needed file is not committed)" "$CI_LOG_DIR/pristine-configure.log"
    cmake --build "$tmp/build" -j "$CI_JOBS" > "$CI_LOG_DIR/pristine-build.log" 2>&1 \
        || ci_fail pristine "a fresh checkout of HEAD does not build" "$CI_LOG_DIR/pristine-build.log"
    local saved="$CI_TEST_CMD"
    CI_TEST_CMD="$(printf '%s' "$saved" | sed "s|\$CI_BUILD_DIR|$tmp/build|g")"
    if ! run_tests "$tmp/build" "$CI_LOG_DIR/pristine-tests.log"; then
        ci_fail pristine "tests fail on a fresh checkout of HEAD" "$CI_LOG_DIR/pristine-tests.log"
    fi
    CI_TEST_CMD="$saved"
    tail -n 2 "$CI_LOG_DIR/pristine-tests.log" | sed 's/^/      /'
    if [ "$CI_KEEP_TMP" = "1" ]; then
        printf '    kept: %s\n' "$tmp"
    else
        rm -rf "$tmp"
    fi
    ci_pass pristine
}

cleanup() {
    local dir
    if [ "$CI_KEEP_TMP" != "1" ]; then
        for dir in "${RUN_TMP_DIRS[@]:-}"; do
            [ -n "$dir" ] && [ -d "$dir" ] && rm -rf "$dir"
        done
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- dispatch
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --list)
            printf 'default stages: %s\n' "$CI_DEFAULT_STAGES"
            # Derived from the defined functions, so this cannot drift from the stages
            # the script actually implements.
            printf 'stages:'
            for fn in $(declare -F | awk '{print $3}' | grep '^stage_' | sed 's/^stage_//' | sort); do
                printf ' %s' "$fn"
            done
            printf '\n'
            exit 0 ;;
        --require-clean) REQUIRE_CLEAN=1 ;;
        --allow-untracked) ALLOW_UNTRACKED=1 ;;
        --strict-tools) CI_STRICT_TOOLS=1 ;;
        --write-tidy-baseline) WRITE_TIDY_BASELINE=1 ;;
        -*) printf 'unknown option: %s (try --help)\n' "$1" >&2; exit 2 ;;
        *) STAGES_REQUESTED+=("$1") ;;
    esac
    shift
done

# Accepting inherited findings is its own mode, not a stage: it produces no verdict about
# the tree, only a file (and it exits before the summary so it can never print
# "GATE PASSED" about a run whose tidy stage failed on purpose).
if [ "$WRITE_TIDY_BASELINE" = "1" ]; then
    write_tidy_baseline
    exit 0
fi

if [ ${#STAGES_REQUESTED[@]} -eq 0 ]; then
    # shellcheck disable=SC2206
    STAGES_REQUESTED=($CI_DEFAULT_STAGES)
fi

printf '\033[1mlocal CI\033[0m — %s stage(s): %s\n' "${#STAGES_REQUESTED[@]}" "${STAGES_REQUESTED[*]}"
START=$(date +%s)
for stage in "${STAGES_REQUESTED[@]}"; do
    if ! declare -F "stage_$stage" > /dev/null; then
        printf 'unknown stage: %s (try --list)\n' "$stage" >&2
        exit 2
    fi
    "stage_$stage"
    RAN_STAGES+=("$stage")
done
ELAPSED=$(( $(date +%s) - START ))

summary
printf '\nall %s stage(s) passed in %ss\nGATE PASSED\n' "${#STAGES_REQUESTED[@]}" "$ELAPSED"
