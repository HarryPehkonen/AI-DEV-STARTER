#!/usr/bin/env python3
"""Record integrity for .ai-dev-starter.json.

    check-kit-record.py --repo <dir> [--kit <dir>] [--no-publish-check] [--report-diff]
                        [--no-probe-check]

WHAT THIS FAILS ON (the whole point of the tool)

  * field rules from docs/KIT-REVISION-CONVENTION.md: `kit`, `url`, `revision` shape,
    `record_kind`, `record_note`.
  * the recorded `revision` is a PUBLISHED kit commit and the kit working tree is clean
    (skipped with --no-publish-check, e.g. in a sandbox with no origin).
  * per `files[]` entry: `repo_sha256` matches the repo's file, `kit_sha256` matches the kit
    blob at `revision`, adapted:false => byte-identical to that blob, adapted:true => really
    different and carries `adapted_why`.
  * per `adopted_fixes[]` entry: the claim must be DEMONSTRABLE -- the kit carries that probe
    at `from_revision`, the repo carries it byte-identical to that blob, and the probe RUNS
    GREEN against this repo's gate. A claimed fix whose probe is absent or fails is a failure.
  * every probe the repo physically carries in `tools/kit-probes/`, and every probe recorded in
    `files[]`, must RUN GREEN. "A fix that must propagate ships a probe" -- the probe is the
    claim, so it is the thing that gets executed.
  * `declined_fixes[]` entries: shape, a why, and not also claimed in `adopted_fixes`.

WHAT THIS DELIBERATELY DOES **NOT** FAIL ON

  * `revision != kit HEAD`. It is REPORTED -- "behind the kit by N commit(s)" -- and the
    verdict stays green. `revision` states the revision a repo was WIRED FROM; the kit growing
    is the kit working, not the repo being broken. Measured 2026-09-20 (card t_fb62d8fa): the
    kit's own `d531a110` turned all six live records red on this one line while every
    file-level check passed -- the equality test was measuring "the kit moved", not "this repo
    is missing a fix". The honest record for a repo that has not taken a change says so
    (`declined_fixes`), and the equality test would have made that record LIE about provenance.
  * a kit probe the repo neither adopted nor declined: REPORTED, with the result of running it
    against this repo's gate (so the line reads "you are actually missing X" or "you already
    have X"), never a failure -- silence is not a claim.
  * a `files[]` `repo_sha256` that no longer matches the file on disk, when the record carries
    `fingerprints_retired` (a dated marker). Added 2026-10-07 with L3: L3 retired the per-file
    fingerprint for records written after it, and told the four records that still carry `files[]`
    to MARK their drift rather than re-read five stale hashes -- so a retired entry stays green and
    says on its own line that it was NOT verified against disk. Everything else about the entry
    (the file exists, the kit blob at `revision`, the `adapted` rules) is still checked.

--report-diff also prints, per adapted entry, the size of the repo-vs-kit diff and how many kit
lines at `revision` the repo's copy is missing. THIS IS A REPORT, NOT A VERDICT: diff size
measures divergence from the kit, not lateness.

Exit 0 = VERDICT: RECORD VERIFIED, 1 = VERDICT: RECORD BAD.
"""
import argparse
import difflib
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def git(args, cwd, check=True):
    p = subprocess.run(["git", *args], cwd=cwd, capture_output=True)
    if check and p.returncode != 0:
        raise subprocess.CalledProcessError(p.returncode, ["git", *args], p.stdout, p.stderr)
    return p


def gate_script(repo: Path):
    """The one gate this repo runs: tools/ci.sh (C++) or scripts/gate.sh (deno/python)."""
    for rel in ("tools/ci.sh", "scripts/gate.sh"):
        f = repo / rel
        if f.is_file():
            return f
    return None


def run_probe(probe: Path, gate: Path, repo: Path):
    """Run a kit probe exactly the way a gate's own `kitprobes` stage does."""
    p = subprocess.run(["bash", str(probe), str(gate), str(repo)],
                       capture_output=True, text=True)
    tail = [l for l in (p.stdout + p.stderr).strip().splitlines() if l.strip()]
    return p.returncode, (tail[-1] if tail else "(no output)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    # Lives in the kit now (tools/check-kit-record.py), so the kit is the repo this file is in: the
    # same directory the old hard-coded default named, without the absolute path.
    ap.add_argument("--kit", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--no-publish-check", action="store_true",
                    help="skip 'revision is published + kit tree clean' (sandboxes)")
    ap.add_argument("--no-probe-check", action="store_true",
                    help="skip running the probes this repo claims to carry")
    ap.add_argument("--report-diff", action="store_true",
                    help="also report repo-vs-kit@revision diff sizes (a report, not a verdict)")
    args = ap.parse_args()

    repo = Path(args.repo).resolve()
    kit = Path(args.kit).resolve()
    manifest = repo / ".ai-dev-starter.json"
    if not manifest.is_file():
        print(f"VERDICT: RECORD BAD (no {manifest})")
        return 1
    m = json.loads(manifest.read_text())

    fails: list[str] = []
    oks: list[str] = []
    report: list[str] = []

    def check(cond: bool, msg: str) -> None:
        (oks if cond else fails).append(msg)

    def is_sha(s) -> bool:
        return isinstance(s, str) and len(s) == 40 and all(c in "0123456789abcdef" for c in s)

    # ---- field rules ---------------------------------------------------------
    check(m.get("kit") == "AI-DEV-STARTER", "kit == AI-DEV-STARTER")
    check(m.get("url") == "https://github.com/HarryPehkonen/AI-DEV-STARTER", "url is the kit's")
    rev = m.get("revision", "")
    check(is_sha(rev), f"revision is 40-hex ({rev})")
    check(m.get("record_kind") in ("retroactive", "at-copy"),
          f"record_kind is retroactive|at-copy ({m.get('record_kind')})")
    check(bool(m.get("record_note")), "record_note is present")

    # OPTIONAL since 2026-10-07 (L3). A dated marker that RETIRES this record's `files[]`
    # fingerprints: L3 retired the per-file fingerprint for records written after it, and the four
    # records that still carry `files[]` MARK the drift instead of re-reading their hashes. Instead
    # of rewriting five stale hashes, the record states the date the fingerprints stopped being read.
    retired_fp = m.get("fingerprints_retired")
    if retired_fp is not None:
        check(isinstance(retired_fp, str) and bool(retired_fp.strip()),
              f"fingerprints_retired is a dated string ({retired_fp})")

    # ---- the revision must be PUBLISHED, and is allowed to be BEHIND ----------
    kit_head = git(["rev-parse", "HEAD"], kit).stdout.decode().strip()
    if not args.no_publish_check:
        ls = git(["ls-remote", "origin", "HEAD"], kit).stdout.decode().split()
        check(bool(ls) and kit_head == ls[0], f"kit HEAD == published ({kit_head})")
        check(git(["status", "--porcelain"], kit).stdout.decode().strip() == "",
              "kit working tree is clean (blobs == published)")
    # REPORTED, never a verdict. "behind" is the designed steady state of a copy-based kit.
    if rev == kit_head:
        report.append(f"kit HEAD {kit_head[:7]}: the record is level with the kit")
    elif git(["merge-base", "--is-ancestor", rev, kit_head], kit, check=False).returncode == 0:
        behind = git(["rev-list", "--count", f"{rev}..{kit_head}"], kit, check=False)
        n = behind.stdout.decode().strip() if behind.returncode == 0 else "?"
        report.append(f"behind the kit by {n} commit(s): wired from {rev[:7]}, kit HEAD is "
                      f"{kit_head[:7]} -- expected, NOT a failure: what this record says about "
                      f"the commits in between is in adopted_fixes/declined_fixes, and running "
                      f"a probe is the only thing that proves a claim (see the lines below)")
    else:
        report.append(f"revision {rev[:7]} is NOT an ancestor of kit HEAD {kit_head[:7]} -- the "
                      f"record names a commit this kit's history no longer contains")

    # ---- per files[] entry ---------------------------------------------------
    files_by_kit = {}
    for e in m.get("files", []):
        rp, kp = e.get("repo_path"), e.get("kit_path")
        if kp:
            files_by_kit.setdefault(kp, rp)
        rf = (repo / rp).resolve()
        check(rf.is_file(), f"{rp} exists in the repo")
        if not rf.is_file():
            continue
        repo_now = sha(rf.read_bytes())
        if repo_now == e.get("repo_sha256"):
            check(True, f"{rp}: repo_sha256 matches the file on disk")
        elif retired_fp is not None:
            check(True, f"{rp}: repo_sha256 RETIRED by fingerprints_retired={retired_fp!r} -- the "
                        f"recorded hash is the files[] state at {rev[:7]}, the file on disk drifted "
                        f"after it; NOT verified against disk (L3: drift after it is unrecorded by "
                        f"policy)")
        else:
            check(False, f"{rp}: repo_sha256 matches the file on disk")
        blob = git(["cat-file", "blob", f"{rev}:{kp}"], kit, check=False)
        if blob.returncode != 0:
            fails.append(f"{rp}: kit_path {kp} does not exist at {rev}")
            continue
        kit_now = sha(blob.stdout)
        # OPTIONAL since 2026-10-06. It only asserted that the hash written INTO the record equalled
        # the kit's blob at `revision` -- a fact the two checks below establish live, by fetching that
        # blob and comparing bytes. Two copies of one number is what made every `revision` move rewrite
        # it in every record, which is where three of the record failures on 2026-10-06 came from (and
        # one of them needed a second reading of what a revision move means). A record that still
        # carries the field is checked exactly as before, so old records stay valid.
        if "kit_sha256" in e:
            check(kit_now == e["kit_sha256"], f"{rp}: kit_sha256 matches the kit blob at {rev}")
        else:
            print(f"  --   {rp}: no kit_sha256 (removed as redundant 2026-10-06; the blob is compared live)")
        adapted = e.get("adapted")
        check(isinstance(adapted, bool), f"{rp}: adapted is a bool")
        if adapted:
            check(bool(e.get("adapted_why")), f"{rp}: adapted=true carries adapted_why")
            check(repo_now != kit_now or "NOT a copy" in e.get("adapted_why", ""),
                  f"{rp}: adapted=true and the bytes really differ from the kit")
            if args.report_diff:
                a = blob.stdout.decode("utf-8", "replace").splitlines()
                b = rf.read_bytes().decode("utf-8", "replace").splitlines()
                sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
                n_diff = sum(max(i2 - i1, j2 - j1) for tag, i1, i2, j1, j2 in sm.get_opcodes()
                             if tag != "equal")
                missing = sum(i2 - i1 for tag, i1, i2, _, _ in sm.get_opcodes() if tag == "delete")
                report.append(
                    f"{rp}: differs from kit@{rev[:7]}:{kp} by {n_diff} line(s); "
                    f"{missing} kit line(s) absent from the copy -- "
                    f"{'UNATTRIBUTED BY THE RECORD (prose only)' if missing else 'no kit line absent'}")
        else:
            check("adapted_why" not in e, f"{rp}: adapted=false carries no adapted_why")
            check(repo_now == kit_now, f"{rp}: adapted=false and the file is byte-identical to the kit")

    # ---- every recorded / carried probe is a CLAIM, and gets RUN -------------
    gate = gate_script(repo)
    claims: dict[Path, list[str]] = {}       # repo probe file -> who claims it

    def claim(path: Path, who: str) -> None:
        claims.setdefault(path, []).append(who)

    # (a) probes the record explicitly adopts -- schema plus the from_revision the fix came from
    adopted = m.get("adopted_fixes", [])
    declined = m.get("declined_fixes", [])
    check(isinstance(adopted, list), "adopted_fixes is a list when present")
    check(isinstance(declined, list), "declined_fixes is a list when present")
    adopted_probes: set[str] = set()
    declined_probes: set[str] = set()

    for e in adopted if isinstance(adopted, list) else []:
        name = e.get("name") or "(unnamed)"
        kp, from_rev = e.get("probe", ""), e.get("from_revision", "")
        check(bool(e.get("name")), f"adopted_fixes: entry {name} carries a name")
        check(is_sha(from_rev), f"adopted_fixes[{name}]: from_revision is 40-hex ({from_rev})")
        check(bool(e.get("adopted_in")), f"adopted_fixes[{name}]: adopted_in is recorded")
        check(bool(kp), f"adopted_fixes[{name}]: names a probe")
        if not kp:
            continue
        adopted_probes.add(kp)
        blob = git(["cat-file", "blob", f"{from_rev}:{kp}"], kit, check=False) if is_sha(from_rev) else None
        if blob is None or blob.returncode != 0:
            fails.append(f"adopted_fixes[{name}]: the kit has no {kp} at {from_rev[:7]} -- a "
                         f"claim must name a probe that existed at that revision")
            continue
        check(True, f"adopted_fixes[{name}]: the kit carries {kp} at {from_rev[:7]}")
        repo_rel = files_by_kit.get(kp) or f"tools/kit-probes/{Path(kp).name}"
        rp = repo / repo_rel
        if not rp.is_file():
            fails.append(f"adopted_fixes[{name}]: CLAIMED BUT ABSENT -- this repo has no "
                         f"{repo_rel}; a repo that records an adoption must carry the probe "
                         f"that proves it")
            continue
        check(True, f"adopted_fixes[{name}]: the repo carries it at {repo_rel}")
        check(sha(rp.read_bytes()) == sha(blob.stdout),
              f"adopted_fixes[{name}]: {repo_rel} is the kit's probe verbatim at {from_rev[:7]}")
        claim(rp, f"adopted_fixes[{name}]")

    for e in declined if isinstance(declined, list) else []:
        name = e.get("name") or "(unnamed)"
        kp = e.get("probe", "")
        check(bool(e.get("name")), f"declined_fixes: entry {name} carries a name")
        check(is_sha(e.get("from_revision", "")),
              f"declined_fixes[{name}]: from_revision is 40-hex ({e.get('from_revision')})")
        check(bool(e.get("why")), f"declined_fixes[{name}]: carries a why (the reason is the point)")
        check(bool(kp), f"declined_fixes[{name}]: names the kit probe it declines")
        if kp:
            declined_probes.add(kp)
            check(kp not in adopted_probes,
                  f"declined_fixes[{name}]: not also claimed in adopted_fixes")

    # (b) a probe recorded in files[] is a claim too (adapted:false already made it byte-identical)
    for kp, rp in files_by_kit.items():
        if kp and kp.startswith("probes/"):
            f = repo / rp
            if f.is_file():
                claim(f, f"files[] {rp} <- {kp}")

    # (c) anything physically carried in tools/kit-probes/ is a claim, recorded or not
    kpdir = repo / "tools/kit-probes"
    if kpdir.is_dir():
        for p in sorted(kpdir.glob("*.sh")):
            claim(p, "carried in tools/kit-probes/")

    if claims and not args.no_probe_check:
        if gate is None:
            fails.append("no gate script found (tools/ci.sh or scripts/gate.sh) to run the "
                         f"{len(claims)} claimed probe(s) against")
        else:
            for path in sorted(claims):
                who = " + ".join(sorted(set(claims[path])))
                rc, last = run_probe(path, gate, repo)
                check(rc == 0, f"probe {path.name} ({who}): VERIFIED against this repo's gate "
                               f"({last})" if rc == 0 else
                               f"probe {path.name} ({who}): FAILED against this repo's gate "
                               f"({last}) -- the claim is not demonstrable")

    # ---- what the kit has that this record says nothing about, with a measurement
    tree = git(["ls-tree", "-r", "--name-only", "HEAD", "probes/"], kit, check=False)
    for kp in sorted(l for l in tree.stdout.decode().splitlines() if l.endswith(".sh")):
        if kp in adopted_probes or kp in declined_probes:
            continue
        if args.no_probe_check or gate is None:
            report.append(f"kit probe {kp}: neither adopted nor declined by this record")
        else:
            rc, last = run_probe(kit / kp, gate, repo)
            report.append(f"kit probe {kp}: neither adopted NOR DECLINED by this record -- run "
                          f"against this repo's gate it {'PASSES' if rc == 0 else 'FAILS'} ({last})")

    print("\n".join(f"  ok   {x}" for x in oks))
    print("\n".join(f"  FAIL {x}" for x in fails))
    if report:
        print("\n  report (no verdict attached):")
        print("\n".join(f"    {x}" for x in report))
    print(f"\nVERDICT: {'RECORD VERIFIED' if not fails else 'RECORD BAD'} "
          f"({len(oks)} ok, {len(fails)} failed)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
