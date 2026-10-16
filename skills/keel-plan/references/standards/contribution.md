# Proven work (keel base)

Agents make code cheap. What's valuable is code that is **shown to work** in the place it
will run, for the people who will use it — and that doesn't hand the burden of proving it to
the reviewer. These rules apply to every change, written by a person or an agent.
Agent-assisted work gets more scrutiny, not less: the code still carries the author's name.

## 1. Prove it works

If it hasn't been run, it doesn't work yet; if it happens to work, that's luck. A change is
proven when:

- it was **run and seen working** (the flow clicked through, the endpoint called, the job run);
- an **automated test** covers what changed;
- that test **fails when the change is reverted** — otherwise it doesn't test the change
  (`scripts/prove.sh` checks this);
- the **edges** are defined: empty, zero, limits, duplicates, failure of a dependency, the
  worst path — not only the happy path.

The PR carries the **evidence**: what was run and what came out, the revert check, the
edges covered. "Tests pass" alone is not evidence.

## 2. Abstractions that hold together

- You can explain the change in plain words, start to finish and each part on its own.
- Inputs, outputs and what happens with unexpected input are explicit.
- **Names are contracts.** A name that says more or less than the thing does is a bug
  (`VersionedRequest` that accepts unversioned ones). If a name needs "but actually…" in a
  comment, rename it.
- It fits the codebase's existing model; it doesn't introduce a parallel vocabulary.
- No invented concepts ("green zone", "the gate", "the key") that exist only to narrate the
  change. Code says what it does in the domain's words.

## 3. Signs of unproven work ("slop")

Each of these is a finding. Mechanical ones are detected by `scripts/slop.sh`.

- Type escape hatches: casting to `any`/`unknown` to silence the compiler, `@ts-ignore`,
  `# type: ignore`, broad lint disables. Types that lie are worse than no types.
- Missing tests for changed behavior, or tests that pass with the change reverted.
- Names that lie; contradictory abstractions; comments that narrate instead of explain.
- Generated-sounding text in code, comments or the PR: dramatic metaphors, filler, a PR
  description that reads like a summary prompt instead of an explanation of what and why.
- Leftover debug output, commented-out code, `TODO` without an owner or ticket.
- "Fix it later" shortcuts. A sloppy change costs more review and maintenance time than it
  saved; speed without quality is negative value.

## 4. Before calling it ready

Answer each with evidence, not intent. If any answer is "no" or "not sure", it isn't ready.

1. Have I seen it work — actually run it, not just read it?
2. Do the types tell the truth?
3. Would someone reading the names in six months understand them correctly?
4. Did I test the edges and the worst path?
5. Could I walk a colleague through every line?
6. If this breaks at 3 AM, will the person on call find the logs, traces and docs they need
   to understand what happened — even if that person isn't me?

## 5. Review until it's clean

One pass is rarely enough. For medium-risk and above: review the full change with fresh
eyes, fix what's found, and repeat **until two consecutive passes find nothing, or four
passes are done** (then stop and say what's left). Review comments from others get a reply:
fixed (how) or not fixing (why).
