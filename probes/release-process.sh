#!/usr/bin/env bash
# guards: templates/cpp/release.sh
#
# Kit-conformance probe for the kit fix of 2026-10-04: the release process itself.
# Before it, "how a release is made" lived in one person's head: the declared version sat
# at 1.0.1 while v1.3.1 was already tagged, and notes were written from memory or not at
# all. The fix is a script: the version has one home, the notes lead with a compatibility
# table, and publish REFUSES while that table is still a placeholder — because how an
# existing user is affected is a judgement, and a generated answer would be confidently
# wrong.
#
#   probes/release-process.sh <path/to/release.sh> [repo-root]
#
# Same reasoning as probes/tidy-baseline.sh: a repo's copy of a kit file is a FORK, so a
# hash or a diff answers "does it differ", never "is it missing the fix". The fix's
# contract can be checked either way. Name-level, plus behaviour where it is cheap. No kit
# checkout, no network, no build, under a second.
#
# What it does NOT do: it never tags, pushes or publishes, and it cannot see a semantic
# regression inside a function that is still present.
#
# Exit 0 = PROBE VERIFIED, 1 = PROBE FAILED.
set -uo pipefail

S=${1:?usage: release-process.sh <release-script> [repo-root]}
[ -f "$S" ] || { echo "PROBE FAILED (no such script: $S)"; exit 1; }
ROOT=${2:-$(cd "$(dirname "$S")/.." && pwd)}
fails=0
oks=0

check() {  # check <rc> <description>
    if [ "$1" -eq 0 ]; then oks=$((oks + 1)); printf '  ok   %s\n' "$2"
    else fails=$((fails + 1)); printf '  FAIL %s\n' "$2"; fi
}

printf '=== probe: release-process fix contract\n'
printf '    script: %s\n    root:   %s\n' "$S" "$ROOT"

# P1 — the four commands are real dispatch branches, not prose in a comment.
grep -qE '^ *status\)'  "$S"; check $? "status is a dispatch branch"
grep -qE '^ *prepare\)' "$S"; check $? "prepare is a dispatch branch"
grep -qE '^ *notes\)'   "$S"; check $? "notes is a dispatch branch"
grep -qE '^ *publish\)' "$S"; check $? "publish is a dispatch branch"

# P2 — declared_version() BEHAVES on a real CMakeLists, and reads it loosely.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed -n '/^declared_version() {/,/^}/p' "$S" > "$TMP/dv.sh"
printf 'cmake_minimum_required(VERSION 3.16)\nproject(MyLib VERSION 0.4.2 LANGUAGES CXX)\n' > "$TMP/CMakeLists.txt"
OUT=$(cd "$TMP" && bash -c 'source ./dv.sh 2>/dev/null; declared_version || echo __NO_FN__')
printf '    declared_version() -> %s\n' "${OUT:-<empty>}"
case "$OUT" in
    0.4.2) oks=$((oks + 1)); printf '  ok   declared_version() reads project(<name> VERSION x.y.z) out of CMakeLists.txt\n' ;;
    *)     fails=$((fails + 1)); printf '  FAIL declared_version() returned "%s", not 0.4.2 — the version read is broken or hardcoded\n' "${OUT:-<empty>}" ;;
esac

# P3 — the judgement gate: publish refuses while the compatibility table is a placeholder.
grep -qE "grep -q 'TODO'.*die" "$S"
check $? "publish is BLOCKED by an unfilled compatibility table (not merely asked politely)"

# P4 — the project name is READ from CMakeLists.txt, so nothing has to be configured.
grep -q 'PROJECT=$(sed' "$S"
check $? "the project name is read from CMakeLists.txt, not hardcoded per repo"

# P5 — the scaffolded table carries the dimensions a user is affected along.
grep -q 'compiles against the public headers' "$S"
check $? "the notes scaffold has the source-compatibility row"
grep -q 'ABI/soname' "$S"
check $? "the notes scaffold has the ABI/soname row"

# P6 — publish re-stamps the released date and commit, so an old draft cannot lie.
grep -qE 'sed -i .*_Released' "$S"
check $? "publish re-stamps _Released with the date and the commit at publish time"

# P7 — the refusal chain that stops a half-finished release leaving the machine.
grep -q 'working tree is dirty' "$S"
check $? "publish refuses a dirty tree"
grep -q 'HEAD differs from origin/main' "$S"
check $? "publish refuses when HEAD is not what origin/main has"

printf 'PROBE %s (%d ok, %d failed)\n' \
    "$([ "$fails" -eq 0 ] && echo VERIFIED || echo FAILED)" "$oks" "$fails"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
