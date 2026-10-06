#!/usr/bin/env bash
# guards: PLUNK-IN.md
# guards: .gitignore
#
# Kit-conformance probe for the kit fix of 2026-10-06: the gate-footprint recipe must use
# SLASH-FREE patterns.
#
# WHY A PROBE AND NOT A HASH: the same reason as every other probe here. A repo's .gitignore
# is its own file, so no byte comparison against the kit can say whether the COPY carries the
# fix. What the copy can be held to is the contract below, in whatever form it has it.
#
# THE CONTRACT. The C++ gate's `tree` stage audits the paths the gate itself creates —
# templates/cpp/ci.sh: `for path in "$CI_BUILD_DIR" "$CI_ASAN_BUILD_DIR" "$CI_TSAN_BUILD_DIR"
# "$CI_RELEASE_BUILD_DIR" "$CI_LOG_DIR" ".ci.env"` (defaults: build build-asan build-tsan
# build-release .ci-logs .ci.env) — and `tree` runs FIRST, so on a fresh clone it asks the
# question before anything has created them. `git check-ignore` cannot match a DIRECTORY-ONLY
# pattern against a path that does not exist, so a recipe of `build/` reads NOT ignored on the
# first run and passes on the second one. Measured on git 2.47.3, same path, directory absent:
# `build/` NOT IGNORED, `build` ignored. The failure message ("the next run would fail on its
# own log files") then names a problem the reader cannot find in their .gitignore, because the
# rule IS there — it just carries a trailing slash.
#
# WHAT IT CHECKS
#   P1  the recipe ignores every path the gate audits, with none of them on disk
#   P2  NEGATIVE CONTROL — the pre-fix form (`build/` etc.) does NOT: 5 of 6 come back NOT
#       ignored. If the control passed too, slash-free patterns would be asserting nothing
#   P3  the audit loop still names the six paths P1 tested (SKIP, printed, when no gate script
#       is reachable — normal outside the kit)
#
# WHICH FILE IT READS. The kit's own runner passes the guarded file: PLUNK-IN.md (the recipe
# is extracted from the step-3 fenced block) or .gitignore (read straight through). A repo's
# `kitprobes` stage passes its GATE SCRIPT instead, and then the recipe checked is that repo's
# own .gitignore — which is the point: the fix propagates as a check on each copy's recipe.
#
# Exit 0 = PROBE VERIFIED, 1 = PROBE FAILED.
set -uo pipefail

G=${1:?usage: gitignore-footprint.sh <PLUNK-IN.md|.gitignore|gate-script> [repo-root]}
[ -f "$G" ] || { printf 'PROBE FAILED (no such file: %s)\n' "$G"; exit 1; }
ROOT=${2:-$(cd "$(dirname "$G")" && pwd)}
FP="build build-asan build-tsan build-release .ci-logs .ci.env"   # the gate's defaults

fails=0
oks=0
check() {  # check <rc> <description>
    if [ "$1" -eq 0 ]; then oks=$((oks + 1)); printf '  ok   %s\n' "$2"
    else fails=$((fails + 1)); printf '  FAIL %s\n' "$2"; fi
}

printf '=== probe: the gate-footprint recipe is slash-free\n'

case "$(basename "$G")" in
    PLUNK-IN.md) SRC="$G";              FROM="PLUNK-IN.md step 3, the fenced block"; GATE=$ROOT/templates/cpp/ci.sh ;;
    .gitignore)  SRC="$G";              FROM="read straight through";                 GATE=$ROOT/templates/cpp/ci.sh ;;
    *)           SRC="$ROOT/.gitignore"; FROM="this repo's own copy";                 GATE=$G ;;
esac
printf '    recipe: %s\n    source: %s\n' "$SRC" "$FROM"
[ -f "$SRC" ] || { printf 'PROBE FAILED (no recipe to read at %s)\n' "$SRC"; exit 1; }

if [ "$(basename "$G")" = "PLUNK-IN.md" ]; then
    BODY=$(awk '/^## Step 3 /{s=1} s&&/<<.EOF.$/{g=1;next} g&&/^EOF$/{exit} g' "$SRC")
else
    BODY=$(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$SRC")
fi
lines=$(printf '%s\n' "$BODY" | grep -c .)
check $([ "$lines" -gt 0 ] && echo 0 || echo 1) "the recipe has body lines to test ($lines)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

unignored() {  # how many footprint paths does the .gitignore in THIS directory not ignore?
    local p n=0
    for p in $FP; do git check-ignore -q "$p" 2>/dev/null || n=$((n + 1)); done
    printf '%s' "$n"
}
scratch() {  # scratch <recipe-body-file> — a repo with NONE of the six paths on disk
    rm -rf "$TMP/repo"
    mkdir -p "$TMP/repo"
    cd "$TMP/repo" || exit 1
    git init -q . >/dev/null 2>&1
    cp "$1" .gitignore
}

printf '%s\n' "$BODY" > "$TMP/shipped"
scratch "$TMP/shipped"
n=$(unignored)
for p in $FP; do
    printf '       %-14s %s\n' "$p" "$(git check-ignore -v "$p" 2>/dev/null | sed 's/\t/ /g')"
done
check $([ "$n" -eq 0 ] && echo 0 || echo 1) "every path the gate audits is ignored before it exists ($n of 6 not ignored)"

printf '.ci-logs/\nbuild/\nbuild-*/\n.ci.env\n' > "$TMP/pre-fix"
scratch "$TMP/pre-fix"
control=$(unignored)
check $([ "$control" -eq 5 ] && echo 0 || echo 1) "negative control: the pre-fix recipe fails on $control of 6 (5 expected — otherwise this probe asserts nothing)"

if [ -f "$GATE" ]; then
    grep -qF 'for path in "$CI_BUILD_DIR" "$CI_ASAN_BUILD_DIR" "$CI_TSAN_BUILD_DIR" "$CI_RELEASE_BUILD_DIR" "$CI_LOG_DIR" ".ci.env"' "$GATE"
    check $? "the gate still audits exactly these 6 paths ($GATE)"
else
    printf '  SKIP the gate audit list — no gate script at %s (normal in a non-kit checkout)\n' "$GATE"
fi

printf 'PROBE %s (%d ok, %d failed)\n' \
    "$([ "$fails" -eq 0 ] && echo VERIFIED || echo FAILED)" "$oks" "$fails"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
