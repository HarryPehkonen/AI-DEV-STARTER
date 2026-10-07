# examples/ — the bash gates, kept as the no-engine fallback

Everything here is one thing: **a gate you copy into your repo and then own.** Until
2026-10-06 that was how the whole fleet worked, and every repo that took one drifted:
a copied gate is a *fork*, not a copy. Measured against the kit's blob at the time, the
four real C++ forks differed by **60, 89, 582 and 586 lines** — and nothing parses the
prose that explains the differences, so no diff and no hash can tell a deliberate local
decision from being one fix behind.

What replaced it is the **engine/policy split**: the gate *policy* is `gate.toml` in the
repo (stages, tiers, failure rules), and the *engine* is `kit-ci`, one binary per machine.
A repo now carries policy only — there is no gate file to fork, so there is nothing to
drift. All twelve gated repos on this fleet were converted on 2026-10-05/06; the adoption
guide is `PLUNK-IN.md` step 2 here, and `KitCI/docs/GETTING-STARTED.md`.

| here | what it is | was |
|---|---|---|
| `cpp/ci.sh` | the C++ gate: two tiers, eleven stages | `templates/cpp/ci.sh` |
| `cpp/.ci.env.example` | every knob the C++ gate has, with defaults and why | `templates/cpp/.ci.env.example` |
| `python/gate.sh` | Python gate: lint → format → tests → types → clean environment → identity | `templates/python/gate.sh` |
| `deno/gate.sh` | Deno gate: lint → tests → format → identity | `templates/deno/gate.sh` |
| `hooks/pre-commit`, `hooks/pre-push` | the two hooks that dispatch to the gate a repo has | `templates/hooks/*` |

**These are still maintained, and they are still the right answer for one case:** a machine
that cannot build the engine. Copy from here exactly as `PLUNK-IN.md` describes, and the
kit's remaining probes (a fix that must propagate ships a probe — `PLUNK-IN.md` step 9)
apply to your copy as they always did.

One thing went with the conversion and is worth knowing before you take a gate from here:
seven probes were retired on 2026-10-07 because their subject was the *copied gate* — and a
gate taken from this directory IS a copied gate, so they are the checks you would want. They
are recoverable from the kit's history:

```bash
git -C <kit> log --diff-filter=D --name-only --oneline -- probes/
git -C <kit> show <the commit before the deletion>:probes/tidy-baseline.sh > tools/kit-probes/tidy-baseline.sh
```

`docs/KIT-FIXES.md` → "Retired fixes" names all seven and, for each, where the guarantee lives
in the engine's world — the row is also the description of what the probe checked.

The gate bodies' own comments still name the probes they were written against (`probes/git-index-file.sh`
appears in all three). Those probes retired on 2026-10-07; the comments are left as written, because
the fixes they describe are still in the code right below them.

Two hooks ship here and they are the OLD shape, which a converter must know: they dispatch to
`tools/ci.sh` (C++) or `scripts/gate.sh` (Deno/Python) and the C++ hook passes a stage tier
as a positional word, while a converted repo's `.githooks/` names the tier of a `gate.toml`
(`scripts/gate.sh --tier fast`). Take the hooks from a converted repo when you take the
engine; take them from here when you take a gate from here.

Everything that is *not* a gate stayed where it was, because it is still copied today:
`templates/CLAUDE.md.template`, `templates/REVIEW.md.template`,
`templates/cpp/release.sh` (the release process, `PLUNK-IN.md` step 10) and
`templates/cpp/version.hpp.in`.
