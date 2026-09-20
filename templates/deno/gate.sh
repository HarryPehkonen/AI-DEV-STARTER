#!/usr/bin/env bash
#
# The gate — run this before you push (and before you deploy).
#
# from AI-DEV-STARTER (plunk-in kit) — if you edit this file, say why in INCIDENTS.md.
#
# Why this file exists instead of CI: the checks that keep this project honest are
# cheap (a few seconds) and they belong to the repo, not to somebody else's account.
# One definition, three callers:
#
#   1. a human, by hand            scripts/gate.sh
#   2. git, on commit and on push  .githooks/pre-commit, .githooks/pre-push
#                                  (arm once per clone: git config core.hooksPath .githooks)
#   3. a clean checkout elsewhere  a nightly job: fresh `git clone` into a temp dir,
#                                  then this same script
#
# Running the SAME file in all three places is the point: "the gate passed" then means
# one thing no matter who says it.
#
# It reports EVERY failure rather than stopping at the first, so one run tells you
# everything that is wrong.
#
# The one invariant (rung 4 of the ladder): the version the browser is told to cache
# under and the version the service worker declares are two copies of one number, and
# they must agree. A mismatch is a deploy that silently never lands on a phone.
#
# Bypass deliberately, never accidentally:  git push --no-verify
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
export PATH="$HOME/.deno/bin:$PATH"
# No colour: the gate greps its own tools' output, and ANSI escapes defeat both the
# greps here and any log this is piped into.
export NO_COLOR=1
export DENO_NO_UPDATE_CHECK=1

# The artifact-identity pair. Point these at your project's copies of the one number,
# or delete the artifact_identity stage and say why in INCIDENTS.md.
VERSION_FILE=${VERSION_FILE:-public/version.js}
CACHE_FILE=${CACHE_FILE:-sw.js}

status=0
step() { printf '\n== %s\n' "$1"; }
fail() { printf 'GATE FAILED: %s\n' "$1" >&2; status=1; }

# The runtime is not a cosmetic tool: with no deno there is nothing to check, and a
# "pass" would be a lie. This is the one thing that fails instead of skipping.
if ! command -v deno >/dev/null 2>&1; then
  printf 'GATE FAILED: deno is not on PATH (looked in $HOME/.deno/bin too) — nothing could be checked\n' >&2
  printf 'GATE FAILED\n' >&2
  exit 1
fi

# The files this branch touches. Used by the format stage: the repo has pre-existing
# non-compliant files, and formatting the whole tree every run buries the signal in
# noise nobody edited.
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  base="$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse HEAD)"
  touched="$(
    { git diff --name-only --diff-filter=ACMR "$base" HEAD
      git diff --name-only --diff-filter=ACMR HEAD
      # New files are invisible to `git diff` until they are staged, so without this
      # line a brand-new file's formatting is never checked at the moment it is
      # written — only after it has already been committed.
      git ls-files --others --exclude-standard
    } | sort -u
  )"
  # A clean checkout (the nightly job, or any clone sitting exactly on origin/main) is
  # not "ahead of" anything, so the diffs above are empty and the checks below would
  # silently pass on files nobody looked at. Fall back to the last commit that landed.
  if [ -z "$touched" ]; then
    touched="$(git show --name-only --pretty=format: HEAD | sed '/^$/d')"
    late_note=" (last commit, since this checkout is level with origin/main)"
  fi
else
  # No commits yet: the first commit's files are in the index and nowhere else.
  touched="$(git diff --cached --name-only --diff-filter=ACMR)"
  late_note=" (first commit)"
fi

# ---------------------------------------------------------------- 1. lint
# Quiet on success: one line. Loud on failure: the rules, verbatim.
step "lint"
lint_out="$(deno task lint 2>&1)"; lint_rc=$?
if [ "$lint_rc" -ne 0 ]; then
  printf '%s\n' "$lint_out" | grep -vE "^Task lint" | head -60
  fail "deno task lint (the rules above)"
else
  printf '%s\n' "$lint_out" | grep -E "Checked [0-9]+ files|Found 0 problems" || echo "clean"
fi

# ---------------------------------------------------------------- 2. tests
# The suite is not only pure functions: it should also hold the contract guards
# (client URL vs server route, payload keys, response shapes) — the checks that catch
# a component/API mismatch no pure-function test can see.
step "tests"
test_out="$(deno task test 2>&1)"; test_rc=$?
if [ "$test_rc" -ne 0 ]; then
  printf '%s\n' "$test_out" | grep -E "FAILED|error:|AssertionError|Diff" | head -40
  fail "deno task test (failures above; full output: deno task test)"
else
  printf '%s\n' "$test_out" | grep -E "^(ok|FAILED) \||[0-9]+ passed" | tail -1
fi

# ---------------------------------------------------------------- 3. format (touched files only)
files="$(printf '%s\n' "$touched" | grep -E '\.(js|ts|css|html|json|jsonc|md)$' || true)"
step "format ($(printf '%s\n' "$files" | grep -c . ) changed file(s) of this branch)"
if [ -n "$files" ]; then
  # shellcheck disable=SC2086
  deno fmt --check $files || fail "deno fmt --check (fix: deno fmt $files)"
else
  echo "nothing to check"
fi

# ---------------------------------------------------------------- 4. artifact identity
# Two copies of one number: APP_VERSION in the browser-side version file and
# CACHE_NAME in the service worker. If they disagree, a phone with the old worker
# cached keeps serving the old build forever — the deploy looks green and is invisible.
step "artifact identity ($VERSION_FILE <-> $CACHE_FILE)"
if [ ! -f "$VERSION_FILE" ] || [ ! -f "$CACHE_FILE" ]; then
  printf '  missing: %s\n' "$(for f in "$VERSION_FILE" "$CACHE_FILE"; do [ -f "$f" ] || printf '%s ' "$f"; done)"
  fail "the artifact-identity pair is not both present — point VERSION_FILE/CACHE_FILE at this project's pair, or delete this stage and record why in INCIDENTS.md"
else
  app_version="$(sed -n 's/.*APP_VERSION *= *["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/p' "$VERSION_FILE" | head -1)"
  cache_name="$(sed -n 's/.*CACHE_NAME *= *["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/p' "$CACHE_FILE" | head -1)"
  if [ -z "$app_version" ] || [ -z "$cache_name" ]; then
    printf '  %s: APP_VERSION=%s   %s: CACHE_NAME=%s\n' "$VERSION_FILE" "${app_version:-<not found>}" "$CACHE_FILE" "${cache_name:-<not found>}"
    fail "could not read both numbers (the sed patterns expect APP_VERSION = \"...\" / CACHE_NAME = \"...\")"
  elif [ "$app_version" != "$cache_name" ]; then
    printf '  %s says %s, %s says %s\n' "$VERSION_FILE" "$app_version" "$CACHE_FILE" "$cache_name"
    fail "APP_VERSION and CACHE_NAME disagree (bump both, from the same edit)"
  else
    printf '  %s == %s == %s\n' "$VERSION_FILE" "$CACHE_FILE" "$app_version"
  fi
fi

# A public/ change without a version bump is a deploy that stays invisible on a phone
# that has the service worker cached. app_version == cache_name keeps the two copies
# honest; this keeps the bump from being forgotten in the first place.
changed_public="$(printf '%s\n' "$touched" | grep '^public/' || true)"
if [ -n "$changed_public" ]; then
  if printf '%s\n' "$changed_public" | grep -qx "$VERSION_FILE"; then
    echo "  public/ changed, and $VERSION_FILE was bumped"
  else
    printf '%s\n' "$changed_public" | sed 's/^/  touched: /'
    fail "public/ changed without bumping $VERSION_FILE (and CACHE_NAME in $CACHE_FILE)"
  fi
else
  echo "  no public/ changes"
fi

if [ "$status" -eq 0 ]; then
  printf '\nGATE PASSED%s\n' "${late_note:-}"
else
  printf '\nGATE FAILED - do not push this\n' >&2
fi

exit "$status"
