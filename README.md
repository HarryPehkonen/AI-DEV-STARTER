# AI-DEV-STARTER — the plunk-in professional upgrade

The minimum file set that takes any repo (new or existing, Deno / Python / C++) from
zero process to **rung 5** of the ladder below: a written agent contract, contract tests
that matter, every incident turned into an enforced check, and one gate script run by
hand, by git on commit/push, and on a clean checkout.

No CI service. No account. No network. The checks live in the repo and cost seconds.

**Who it is for:** one developer working with a coding agent (Claude Code, Codex, a
Hermes session) on a repo with no hosted CI — where the build commands get re-derived
every session, the same mistake gets made twice, and "the gate passed" means something
different on each machine.

This kit is the generalization of two real, working instances: a 126-commit
Deno/Oak/Postgres app and two C++ projects. It is deliberately smaller than either —
it is what those repos needed on **day one**, not what they accumulated in a year.

---

## The ladder — the eight rungs, and what each one prevents

| # | Rung | What it prevents |
|---|---|---|
| 1 | **Write the contract for the agent** — one `CLAUDE.md`: exact commands, architecture, a gotchas list | the same mistake being made twice, and every new session re-deriving the build commands |
| 2 | **Write a brief before delegating** — goal, constraints, wire formats, acceptance condition, committed | an agent run you cannot resume after it is capped or killed, and work that answers a question you did not ask |
| 3 | **Test what actually breaks** — the contracts (client call ↔ server route, response shape, version consistency, auth), not just pure functions | a green suite of 700 tests over a client calling a route the server never served |
| 4 | **Turn every incident into a check, and write the incident next to it** | the same outage twice — and the check being deleted by the next hurried contributor because it looks arbitrary |
| 5 | **One gate script, N callers** (by hand, by git hook, on a clean checkout) | "the gate passed" meaning three different things on three machines |
| 6 | **Verify production, not just the tree** — probe the deployed system for wire-only invariants | a green tree and a deploy that has been broken since Tuesday; silent when healthy |
| 7 | **Script the deploy, then verify it live** — fixed steps, idempotent schema, a post-deploy check a human runs | the manual step that gets skipped at 23:00 under pressure |
| 8 | **Every recurring check is a scheduled job** with an owner and a delivery target | a check that exists on paper and has not actually run since the day it was written |

**This kit is rungs 1–5.** Rungs 6–8 are per-project and per-host: a deploy script and a
nightly job cannot be templated from outside the project, and pretending otherwise is
how a starter kit becomes a framework nobody uses.

---

## What is in the box

| File | What it is |
|---|---|
| `README.md` | this file — the ladder, the gate contract, how to plunk it in |
| `PLUNK-IN.md` | the copy-paste checklist that upgrades an existing repo, per language |
| `INCIDENTS.md` | the incident-log convention, the kit's own incidents, and one worked example |
| `templates/CLAUDE.md.template` | the agent contract doc, with the gotchas section pre-shaped |
| `templates/deno/gate.sh` | Deno gate: lint → tests → format (touched) → artifact identity |
| `templates/python/gate.sh` | Python gate: lint → format (touched) → tests → types → a clean environment (a wheel in a fresh venv, or `requirements.txt` + the suite from a fresh venv) → identity |
| `templates/cpp/ci.sh` | C++ gate, two tiers and eleven stages (copy of the proven one) |
| `templates/cpp/.ci.env.example` | every knob the C++ gate has, with defaults and why |
| `templates/hooks/pre-commit` | fast tier — runs on `git commit` |
| `templates/hooks/pre-push` | full tier — runs on `git push` |
| `probes/<slug>.sh` | one per kit fix that must propagate: takes a gate script and exits non-zero when that fix is missing from it |
| `tools/kit-probes.sh` | the kit's own run of every probe, against the kit file(s) it guards — one run per `# guards:` line (`--list` shows what each one checks) |

Both hook files dispatch to whatever gate the repo has (`tools/ci.sh` for C++,
`scripts/gate.sh` for Deno/Python), so the same two hooks can be copied into any repo.

A copied repo does not sync itself, so **a fix that must propagate ships a probe**: the
probe is copied into the repo as `tools/kit-probes/<slug>.sh`, and the gate's `kitprobes`
stage runs every probe it finds there against itself. It needs no kit checkout, no network
and no build, and it fails the push on the machine that would otherwise have pushed the lag.
`PLUNK-IN.md` step 9 has the rule, the why, and the limits.

---

## The gate contract — six rules every template satisfies

1. **Reports EVERY failure, not just the first.** One run tells you everything that is
   wrong: the Deno and Python gates run every stage and accumulate; the C++ gate reports
   everything wrong inside a failing stage, stops, and then **names every stage that did not
   run** (`BLOCK <stage> (did not run)`) — a stage that never ran must never read as green
   (see `DESIGN-NOTES.md` D6 for why that is the honest reading of this rule).
2. **One script, runnable in three places:** by hand, by git on commit and push, and on
   a clean checkout elsewhere (nightly job). The same file in all three — that is what
   makes "the gate passed" mean one thing.
3. **One unambiguous final line:** `GATE PASSED` or `GATE FAILED`. Grep for it; never
   read a run as "probably fine".
4. **`export NO_COLOR=1`** and no update checks: the script greps its own tools' output,
   and ANSI escapes and update banners defeat greps.
5. **Non-zero exit on failure** (so a hook, a cron job, or a human's `&&` chain obeys it).
6. **Format and type steps check ONLY the files the branch touched.** Every real repo
   has pre-existing violations; a whole-tree check buries the signal under noise nobody
   edited, and the gate gets muted within a week.

---

## The invariant — two copies of one number must agree

Every project in this kit has exactly **one** artifact-identity check: a single number
that exists in two places and must match. It is the cheapest possible guard against the
most common silent failure — a build that is green while shipping something stale.

Python has **two shapes of pair**, because the gate handles two kinds of Python repo and
uses whichever pair the repo actually has (the gate prints which branch it took on its
first line; see `PLUNK-IN.md` step 4):

| Language | The pair | Where the gate checks it |
|---|---|---|
| Deno | `public/version.js` `APP_VERSION` ↔ `sw.js` `CACHE_NAME` | `artifact identity` stage |
| Python, packaged (`pyproject.toml`) | `pyproject.toml` `version` ↔ the `__version__` of the **installed wheel** | `artifact identity` stage |
| Python, unpackaged (`requirements.txt`) | the tracked `VERSION` file ↔ the `__version__` **the code reports** | `artifact identity` stage |
| C++ | `project(<name> VERSION x.y.z)` ↔ the CMake-generated version header | `version` stage |

Point the check at your project's pair in `PLUNK-IN.md` step 4, or delete that stage —
but if you delete it, write down why in `INCIDENTS.md`.

---

## Why a rationale file is not optional

A check with no written reason looks arbitrary to whoever meets it next, and arbitrary
checks get deleted — usually by the person in a hurry, which is exactly the person who
re-introduces the bug. So every check in this kit carries its incident (`INCIDENTS.md`),
and every rule in the agent contract carries its gotcha. **The rationale is load-bearing.**

---

## Plunk it in

Read `PLUNK-IN.md`. The short version, for a repo that already has a git history:

```bash
# 1. the two hooks (they dispatch to whatever gate the repo has)
mkdir -p .githooks
cp <kit>/templates/hooks/pre-commit .githooks/pre-commit
cp <kit>/templates/hooks/pre-push   .githooks/pre-push
chmod +x .githooks/pre-commit .githooks/pre-push
git config core.hooksPath .githooks

# 2. the gate for your language
mkdir -p scripts tools
cp <kit>/templates/deno/gate.sh scripts/gate.sh     # or python/gate.sh, or cpp/ci.sh
chmod +x scripts/gate.sh

# 3. the agent contract and the incident log
cp <kit>/templates/CLAUDE.md.template CLAUDE.md     # then fill every <placeholder>
cp <kit>/INCIDENTS.md .

# 4. run it, and make it pass on the committed tree before you do anything else
scripts/gate.sh
git commit -am "process: plunk in the gate"     # the hook now runs it for you
```

Step 4 is the one that matters. A gate that has never passed on this repo is not a gate
yet — it is a file. The first run will find pre-existing problems; fix them or record
them as accepted findings (see the C++ tidy baseline in `.ci.env.example`), but do not
weaken the gate to get to green.

---

## What is deliberately NOT in this box

- **No CI config.** There is no GitHub Actions file, and no `Makefile` wrapper: the gate
  script *is* the interface. A hosted pipeline cannot run on your commit before the
  commit exists, and every check here is cheap enough to run there.
- **No language-specific lint config.** `.clang-format`, `ruff` settings, and `deno.json`
  tasks are project decisions; the gate runs whatever the repo configures.
- **No test files.** A template test teaches nothing and gets deleted. Rung 3 is the
  per-project work: point the gate at the suite you have, and add the contract tests
  that assert the things that actually broke.
- **No secrets, no hosts, no tokens, no addresses.** The kit is portable and inert.
- **Rungs 6–8.** Deploy verification and nightly jobs are per-project; see the ladder.
