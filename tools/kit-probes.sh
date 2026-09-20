#!/usr/bin/env bash
#
# The kit's own run of its probes — "the kit runs its own" half of the probe rule
# (docs/KIT-REVISION-CONVENTION.md, "So how drift is actually caught: probes").
#
#   tools/kit-probes.sh            every probe in probes/, against the kit file it guards
#   tools/kit-probes.sh --list     what each probe guards, without running anything
#
# Every probe is a standalone script that takes a gate script (and a repo root) and exits
# non-zero when one kit fix is missing from that copy. The probe's own header carries the
# binding: a `# guards: <kit path>` line names the kit file the probe is about, so this
# runner never has to guess and a probe can never be pointed at the wrong file.
#
# The runner is the KIT's. A repo does not copy it: a repo's own gate runs the probes it
# carries straight out of tools/kit-probes/ (the `kitprobes` stage in each template).
#
# Run this before publishing a change to a probe or to a template the probes guard: it is
# the only check that the kit's own artifacts still satisfy the contracts the kit asserts.
#
# Exit 0 = every probe VERIFIED, 1 = at least one PROBE FAILED.
set -uo pipefail

KIT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROBES_DIR=$KIT_ROOT/probes

list_only=0
[ "${1:-}" = "--list" ] && list_only=1
[ $# -gt 0 ] && [ "${1:-}" != "--list" ] && { printf 'usage: tools/kit-probes.sh [--list]\n' >&2; exit 2; }

shopt -s nullglob
probes=("$PROBES_DIR"/*.sh)
shopt -u nullglob

if [ ${#probes[@]} -eq 0 ]; then
    printf 'KIT PROBES: no probes in %s\n' "$PROBES_DIR"
    exit 1
fi

verified=0
failed=0
for probe in "${probes[@]}"; do
    name=$(basename "$probe")
    guards=$(sed -n 's/^# guards: *//p' "$probe" | head -1)
    if [ -z "$guards" ]; then
        printf '  FAIL %s — no "# guards: <kit path>" line, so nothing names what it checks\n' "$name"
        failed=$((failed + 1))
        continue
    fi
    target=$KIT_ROOT/$guards
    if [ ! -f "$target" ]; then
        printf '  FAIL %s — guards %s, which does not exist in the kit\n' "$name" "$guards"
        failed=$((failed + 1))
        continue
    fi
    if [ "$list_only" = "1" ]; then
        printf '  %-24s -> %s\n' "$name" "$guards"
        continue
    fi
    printf '\n--- %s -> %s\n' "$name" "$guards"
    if bash "$probe" "$target" "$KIT_ROOT"; then
        verified=$((verified + 1))
    else
        printf '  (probe exited non-zero)\n'
        failed=$((failed + 1))
    fi
done

if [ "$list_only" = "1" ]; then
    exit 0
fi

printf '\nKIT PROBES: %d VERIFIED, %d FAILED\n' "$verified" "$failed"
[ "$failed" -eq 0 ] || exit 1
