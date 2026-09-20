# Convention — recording the kit revision a repo was wired from

**Why.** The kit (`AI-DEV-STARTER`) is copied by hand into each project. Nothing syncs downstream,
so a defect fixed in the kit stays live in every repo that copied it earlier — which is exactly how
the broken clang-tidy baseline recipe was found four separate times on 2026-09-20 before anyone
noticed it was one bug. This convention makes that class of drift a **deterministic diff** instead of
a hand search.

**What to do.** Every repo that copied artifacts from the kit carries one file at its root:
`.ai-dev-starter.json`. It names the kit revision the repo was wired from and the SHA-256 of every
copied file **as recorded here**, so a later sync card can answer two separate questions without
guesswork:

- *Has the kit moved on?* — compare the kit's current file at `kit_path` against the recorded `kit_sha256`.
- *Has this repo edited its copy locally?* — compare the repo's current file against the recorded `repo_sha256`.

## Where this file lives

**In the kit**, at `docs/KIT-REVISION-CONVENTION.md` in `AI-DEV-STARTER` — read it from a kit
checkout:

```bash
git -C /home/harri/hermes-workspace/AI-DEV-STARTER show HEAD:docs/KIT-REVISION-CONVENTION.md
```

Every citation of that path — a record's `record_note`, a copied gate script, a hook, a probe, or
one of the kit's own files — means **this file, in the kit**. Nothing is copied into a repo, and a
repo's own `docs/` directory (Computo and jsonTools both have one) does not hold it.

*Why this needed saying, 2026-09-20 (card `t_c5e5e11f`):* the file sat loose and untracked at
`/home/harri/hermes-workspace/docs/` while six records and seven kit files cited
`docs/KIT-REVISION-CONVENTION.md` (eight references) — a path that existed in no repo and, as `ls`
showed, in no kit checkout either. An unversioned convention has no history to be checked against,
which is the defect this document exists to prevent, so it moved into the kit and now travels with
the artifacts it governs.

## Exact file shape

```json
{
  "kit": "AI-DEV-STARTER",
  "url": "https://github.com/HarryPehkonen/AI-DEV-STARTER",
  "revision": "<40-hex sha of the kit's PUBLISHED commit this record's files[] were taken at>",
  "recorded_at": "YYYY-MM-DD",
  "record_kind": "retroactive | at-copy",
  "record_note": "one or two sentences: when this repo was wired, and why any file is adapted",
  "adopted_fixes": [
    {
      "name": "tidy-baseline",
      "from_revision": "<40-hex sha of the kit commit that fix came from>",
      "probe": "probes/tidy-baseline.sh",
      "adopted_in": "<the commit in THIS repo that landed it>"
    }
  ],
  "declined_fixes": [
    {
      "name": "optimized-build-stage",
      "from_revision": "<40-hex sha of the kit commit that added it>",
      "probe": "probes/optimized-stage.sh",
      "why": "one line: declined, not applicable, or parked -- with the measurement if there is one"
    }
  ],
  "files": [
    {
      "repo_path": "tools/ci.sh",
      "kit_path": "templates/cpp/ci.sh",
      "repo_sha256": "<sha256sum of this repo's file at record time>",
      "kit_sha256": "<sha256sum of the kit's kit_path at `revision` — re-read at the NEW revision by every commit that MOVES `revision`>",
      "adapted": true,
      "adapted_why": "one line, only when adapted is true"
    }
  ]
}
```

Field rules:

- `revision` is the **published** commit — verify with `git ls-remote origin` against `git rev-parse HEAD`.
  Never record a local-only SHA: a reader must be able to `git fetch` it. It names the revision the
  recorded `files[]` set was last taken from, and it **moves only when the copy genuinely (re)takes
  artifacts from a newer kit commit** (2026-09-20, card `t_fb62d8fa`). It is not a HEAD tracker:
  moving it to make "am I level with the kit?" come out green would make the record claim the repo was
  wired from artifacts it never took. Honestly behind > falsely current.
- `record_kind` is `retroactive` when the repo was wired before the kit was a git repo (the revision is
  the kit's first published commit, *not* the exact copy point — say so in `record_note`), and
  `at-copy` for anything wired from here on.
- `adapted: true` means the repo's copy deliberately differs from the kit's file. `adapted: false`
  means byte-identical. Be accurate: this field is what stops a sync card from "fixing" a local
  decision back to the kit's default (Permuto deliberately declined the `tidy` stage this way).
- `files` lists **only artifacts actually copied from the kit** — the gate script, the hooks,
  `.ci.env.example`, the incident log, the agent contract. Not the repo's own source.
- `adopted_fixes` (optional) — one entry per kit fix this repo has taken since `revision`. Each entry
  is **a claim that must be demonstrable**: the kit has to carry `probe` at `from_revision`, the repo
  has to carry the same probe verbatim (by convention at `tools/kit-probes/<probe's name>`), and the
  checker **runs it** against this repo's gate. A claim whose probe is absent or fails is a record
  FAILURE. This is the only mechanism in the record that can answer *"is this repo missing a fix?"* —
  every hash in `files` answers provenance instead, and cannot.
- `declined_fixes` (optional) — one entry per kit fix this record explicitly does **not** carry:
  declined, not applicable (the fix guards a language or gate this repo does not use), or parked
  pending a human decision. `why` is the authoritative part; put the measurement in it when there is
  one ("the kit's probe fails against this gate: 0 ok, 7 failed"). A probe may be claimed in
  `adopted_fixes` or listed in `declined_fixes`, never both.
- Neither list is required. A kit fix in neither one is not an error — the checker REPORTS it, with
  the result of running the kit's probe against this repo's gate, so the line reads "you are actually
  missing X" or "you already have X". Silence is not a claim, and it is no longer a red line either.

### A `revision` move re-reads EVERY `kit_sha256`, not the ones a card names

`kit_sha256` is the kit's `kit_path` **at `revision`** — the checker hashes the blob at the revision
the record states (`git cat-file blob <revision>:<kit_path>`). So the commit that moves `revision`
must re-read **every** entry in `files[]`, not only the entries the sync card happens to name: the
move spans **every kit commit in between**, and any one of them may have touched a recorded path.

Measured, 2026-09-20 (card `t_c1c5ba6c`, Computo). The jump `951608c → f9c3300` covers two kit
commits, `d531a110` (the `release` stage) and `f9c3300` (the GIT_INDEX_FILE fix), which between
them moved four kit paths a `files[]` entry can name:

| kit commit | kit files it moved that a record can name |
|---|---|
| `d531a110` | `templates/cpp/ci.sh`, `templates/cpp/.ci.env.example`, `templates/hooks/pre-push` |
| `f9c3300` | `templates/cpp/ci.sh`, `templates/deno/gate.sh`, `templates/python/gate.sh`, `INCIDENTS.md` |

(`f9c3300` also moved `tools/kit-probes.sh` — the kit's own runner, which no record lists, so no
`kit_sha256` can go stale from it. The four files above are the ones a record can name.)

So four of Computo's entries needed re-reading — `tools/ci.sh`, `.ci.env.example`,
`.githooks/pre-push`, `INCIDENTS.md` — while the card that ordered the move named two ("the
templates and the kit's incident log"). The checker fails the stale ones with the same line it fails
a genuinely stale record with, which is why the audit belongs in the commit that moves `revision`.

Reproduce it:

```bash
KIT=/home/harri/hermes-workspace/AI-DEV-STARTER
git -C "$KIT" diff --stat 951608c f9c3300 -- templates/ INCIDENTS.md probes/ tools/
for c in d531a110 f9c3300; do git -C "$KIT" show --name-only --format="%h %s" "$c"; done
```

Then, per entry, compare the recorded `kit_sha256` against the blob at **both** revisions
(`git -C "$KIT" cat-file blob <old-rev>:<kit_path>` and `<new-rev>:<kit_path>`). That comparison is
the proof of cause: the old value still matches at the OLD revision, so the entry is stale because
the revision moved, not because the record was wrong when it was written.

Two things this rule is not:

- *Not "re-read the file you ported."* The port is one path among those the jump touched — on
  Computo the fix's own path was `templates/cpp/ci.sh`, one of the four, and the other three moved
  for reasons that had nothing to do with that card.
- *Not a rule about every commit.* A repo-local change that does **not** move `revision` (a new
  stage, a prose fix) moves `repo_sha256` only: `revision` and every `kit_sha256` stay exactly as
  they were, and saying so in `record_note` is what stops the next reader from "fixing" them.

## The rule that keeps it true

**Any future commit that edits a copied artifact must update that artifact's `repo_sha256` in the same
commit** — and any commit that *moves* one must update its `repo_path` too. **A commit that moves
`revision` re-reads every `kit_sha256` in `files[]` in that same commit**, because the move spans every
kit commit in between (see above). A record that is allowed to drift silently is worse than no record.

**Installing a drafted agent contract counts as both.** Two repos currently keep their contract at a
staging path because the protected-file guard refuses unattended writes to `CLAUDE.md` and no human was
present (TNGPlaylists `docs/PROJECT-CONTRACT.md`, docsum `gate-evidence/docsum/contract-doc-final.md`).
jsonTools was the third and has since been installed: the drafted section was applied to its live
`CLAUDE.md` in commit `44c3f6c` (2026-09-20, with Harri's explicit approval — the headless attempt had
been refused, and the draft is kept at `gate-evidence/jsonTools/CLAUDE.md-hooks-section.patch`), so its
`.ai-dev-starter.json` entry points at `CLAUDE.md` itself. Whichever commit finally installs a staged
contract as `CLAUDE.md` must, in that same commit, update that entry's `repo_path` and `repo_sha256` —
otherwise the manifest points at a file that is no longer the one the repo actually uses.

## What a sync card does now

There is one command, and its verdict changed on 2026-09-20 (card `t_fb62d8fa`) after the kit's own
`d531a110` turned all six live records red on a **single** line while every file-level check passed:

```bash
python3 /home/harri/hermes-workspace/gate-evidence/t_0cc793fb/check-kit-record.py --repo <dir>
```

Exit 0 = `VERDICT: RECORD VERIFIED`, 1 = `VERDICT: RECORD BAD`. What it fails on, and what it only
reports:

| | |
|---|---|
| **FAIL** | record-vs-disk drift — a `repo_sha256` that no longer matches the file, a `kit_sha256` that does not match the kit blob at `revision`, `adapted:false` that is not byte-identical, `adapted:true` with no `adapted_why` |
| **FAIL** | a `kit_sha256` left stale by a `revision` move — every entry is compared against the NEW `revision`, so an entry the sync card never named fails exactly as loudly as the one it did (see "A `revision` move re-reads EVERY `kit_sha256`") |
| **FAIL** | **a claimed fix whose probe is absent or fails** — an `adopted_fixes` entry, or a probe recorded in `files[]`, or a probe physically carried in `tools/kit-probes/`, that will not run green against this repo's gate |
| **FAIL** | the kit's HEAD is unpublished or its tree is dirty — a reader could not fetch `revision` |
| **REPORT** | `behind the kit by N commit(s)` — the record states what the repo was wired from; the kit growing is the kit working, not the repo being broken |
| **REPORT** | every kit probe this record neither adopted nor declined, *with the result of running it against this repo's gate* — so the line says whether the repo is actually missing the fix |

Measured on this rule's own edge, 2026-09-20 (card `t_c5e5e11f`): the kit commit that moved this file
into the kit reported `behind the kit by 1 commit(s)` on the four records that had been level with
`f9c3300`, and `3 commit(s)` on the two wired from `951608c` — and moved no verdict. All six were
`RECORD VERIFIED` before it and after it, with only the report lines changing: nothing needed
re-reading, because that commit added `docs/` and touched no recorded `kit_path`. A REPORT is how the
record says "the kit grew"; it is not a hole in the record.

**Do not move `revision` to chase HEAD.** Two consequences follow, and the first is the measurement
that forced the change: the equality test `revision == kit HEAD` was answering *"has the kit moved?"*
and reporting it as *"this repo is broken"*. The second is worse — a repo that has not taken the new
artifacts but bumps `revision` anyway makes the record lie about provenance, which is the one thing it
exists to get right. **Honestly behind > falsely current.**

What the record still is *not*: a drift detector made of hashes. `kit_sha256` matches whenever the kit
has not moved and `repo_sha256` matches whenever nobody edited the copy, so a repo genuinely one fix
behind used to read "nothing to do" (measured 4/4 on real one-fix-behind copies, card `t_0cc793fb`).
And `adapted: true` entries — forks — carry no content signal at all: a one-fix-behind copy is missing
27 kit lines while a verified, current record is missing 125, so **diff size measures divergence from
the kit, not lateness**. Probes are the answer; the hashes answer provenance and intent.

So the sync card's job is one decision per kit fix newer than `revision`, and the record is where that
decision lives:

1. **Adopt it — in TWO commits, not one.** `adopted_fixes[].adopted_in` must name a commit that
   exists, and a commit cannot name itself, so "everything in ONE commit" is not achievable and no
   adoption has ever done it. The measured shape, identical on all four C++ forks (2026-09-20, cards
   `t_0a9a0018` / `t_c1c5ba6c`):

   - **the artifact commit** — the port, its probe at `tools/kit-probes/<probe's name>`, and every
     record field a commit *about this repo* can state: `repo_sha256` for each file it touched, a
     `files[]` entry for the probe, `kit_sha256` re-read for **every** entry whose kit blob moved
     (above), and `revision` **only if** the copy really did (re)take artifacts from the newer kit
     commit. This is where the convention's own rule lands — a commit that edits a copied artifact
     updates the record in the same commit. In all four measured pairs this commit touches
     `.ai-dev-starter.json` *and* the artifacts; the record-only commit touches only the record.
   - **the record-only commit** — one file, `.ai-dev-starter.json`: the `adopted_fixes` entry, with
     `from_revision` = the kit commit the fix came from, `probe` = its kit path, and `adopted_in` =
     the artifact commit's SHA. The checker then demands the claim be demonstrable: the kit carries
     that probe at `from_revision`, the repo carries it byte-identical, and it RUNS GREEN against this
     repo's gate. Nothing else goes in this commit; it exists because `adopted_in` needs a commit
     that has already landed.
   - Measured pairs, artifact commit first: jsonTools `9a60fda` + `0f51c9b`; JSOM `f24ac92` +
     `8694dbb`; Permuto `8541d27` + `9d7fb15`; Computo `a3379f5` + `c60d7fb` (`git log --oneline -2`
     in any of the four shows the pair, and `adopted_in` points at the first).
2. **Decline it** — add a `declined_fixes` entry with the reason, and with the measurement when there
   is one: *"the kit's probe fails against this gate: 0 ok, 7 failed"* is a fact, while *"not needed
   here"* is an opinion that the next reader has to re-derive.
3. **Leave it** — record nothing; the checker reports the fix as neither adopted nor declined. Legal
   and legible, not an error. What is not legal is a `revision` bump that implies something was taken.


### So how drift is actually caught: probes

**A fix that must propagate ships a probe.**

A probe is a small script in the kit that takes a gate script path, and exits non-zero when the fix is
absent — checked by name and by behaviour, not by hash or by diff. The reference implementation is
`probe-tidy-baseline-fix.sh` (the 2026-09-20 clang-tidy baseline fix): it asserts the normaliser exists,
feeds it one synthetic finding and checks the repo root and `:line:col` are stripped, asserts both sides
of the comparison go through it, and asserts `--write-tidy-baseline` shares the same function.

Measured, and it is why this is the mechanism: kit `PROBE VERIFIED 7/7`; all four C++ repos at HEAD
`PROBE VERIFIED` (no false positives); the same four one fix behind `PROBE FAILED`, rc 1. It needs no
kit checkout, no network, no build, runs in under a second — so **each repo's own gate can run it**, which
is the cost a repo-against-kit diff stage cannot avoid (it would go red on 4/4 repos the day it landed:
the forks differ from the kit by 60, 89, 582 and 586 lines, and a fork's only explanation today is prose
in a comment block that nothing parses).

Its limits, honestly: a probe is name- and contract-level, so a semantic regression *inside* a function
that is still present is not caught — that costs a real build and a real run, which is what the port card
did by hand four times. And a probe must be written per fix, so the rule is a discipline, not a free
guarantee.

**Shipped probes (2026-09-20).** `probes/tidy-baseline.sh` (the 7-check reference implementation above)
and `probes/gate-stage-guards.sh` (3 checks). The second is the rule paying for itself: while porting the
first into Computo's fork, that repo's gate printed `all 10 stage(s) passed in 0s / GATE PASSED`, exit
status 0, after executing **one** stage of ten — `set -u` plus `local -a sources` (declared, never
filled) made `"${#sources[@]}"` an unbound-variable error, and bash unwound out of the stage *and* out of
the dispatch loop. A `git push` went through on that verdict. The hole predates the port and lived in every
C++ copy, so the fix (declare such arrays `=()`, fail a stage that returns non-zero without a verdict,
derive the verdict from the stages that RAN) ships with its own probe in the same commit — which is what
"a fix that must propagate ships a probe" means in practice, applied to the mechanism's own discovery.

`probes/optimized-stage.sh` (7 checks, 2026-09-20, card `t_5c2a8ab2`) is the first probe written for a
gap rather than for a bug. Every stage of `templates/cpp/ci.sh` built `CI_BUILD_TYPE` (`Debug` by
default) while the configuration a repo's own pipeline builds is decided elsewhere, so the gate could be
green about a configuration nothing ever compiled — Computo measured that as twelve days of red Pages
deploys behind a green local gate. The fix is a `release` stage that builds a second configuration, and
the probe holds a copy to it by name and by behaviour: the stage exists, its configure passes a build
type that is **not** Debug, its own log is held to the `warning:` rule, the tests run in its own build
dir, it is in `CI_DEFAULT_STAGES`, and the `tree` stage audits that dir. Two things worth copying from it
if you write the next one: its limit is written into its own header (it checks the *default* tier, not a
repo's `.githooks/pre-push`, which spells its own list out — read the hook when porting), and it was run
against six false-fix mutants of the fixed file, each caught by exactly one check, hit for real on
Computo's fork `PROBE VERIFIED 7/7` (no false positive) and on the pre-fix template `PROBE FAILED 0/7`.
Mutant-testing a probe is the part that proves it checks behaviour and not spelling.

`probes/git-index-file.sh` (5 checks, 2026-09-20, card `t_0a9a0018`) holds the three gate templates
to the fix for a **hook handing git's TEMPORARY index to everything the gate runs**: `git commit --
<path>` exports `GIT_INDEX_FILE` (`<repo>/.git/next-index-XXXXXX.lock`) to the pre-commit hook, and
any `git` command the gate runs in ANOTHER repository then reads this repo's index entries against
that repository's object store and dies on the first blob it does not have. It is the first probe
whose fix lands in more than one file: three `# guards:` lines, and `tools/kit-probes.sh` runs a
probe **once per guarded line**, so one probe holds `templates/cpp/ci.sh`, `templates/deno/gate.sh`
and `templates/python/gate.sh` — and a repo that carries it needs no change, because a repo's own
`kitprobes` stage runs the probe against its gate directly. The shape it deliberately does NOT use
is worth recording: "run the gate's `tree`/`format` stages both ways and diff the output" passes
vacuously — measured, those stage outputs are byte-identical with the inherited temporary index and
with the real one, because the defect needs a git command in a *different* repository to be visible
at all. Instead it runs the gate's own environment block inside a real pathspec commit in a
throwaway repo whose hook runs a cross-repo `git status`, and pairs that with the same bytes minus
the `unset` line — which must be REFUSED. The hooks (`templates/hooks/*`) are deliberately not
changed, and that is measured: the pre-commit hook's git call reads its own repo and the gate it
execs does the unsetting, while pre-push never inherits a temporary index (`git push` does not
create one).

## Who writes it

`hermes-dev` only. This file **is** committed — in the kit, at `docs/KIT-REVISION-CONVENTION.md` (see
"Where this file lives" above) — and is pushed through the kit's normal publish lane like any other kit
artifact. It is not itself a *copied* artifact: no record lists it in `files[]`, and a kit commit that
only adds or edits it changes no `kit_sha256` (measured, above). There is no second copy anywhere: a
loose copy beside a repo would be a record allowed to drift silently, which is the thing this document
is about.
