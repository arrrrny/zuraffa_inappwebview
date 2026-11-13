# AGENTS.md

<!-- misfire-rule:begin -->
## ZURAFFA MISFIRE RULE (HARD, NON-NEGOTIABLE — HARDCODED TOP RULE)

**On ANY misfire (test failure, compilation error, runtime crash, unexpected output) related to zuraffa:**

1. **STOP IMMEDIATELY** on the first misfire.
2. **Report the issue** to zuraffa GitHub (`arrrrny/zuraffa`) with: the command that failed, expected vs actual output, and root cause.
3. **Continue with a workaround** to make the task pass (e.g., skip the failing test, use an alternative approach, or mock the failing component).
4. **Add a comment** in the code explaining the workaround applied and linking to the zuraffa GitHub issue.

**On ANY misfire related to the repo itself (not zuraffa):**

1. **STOP IMMEDIATELY** on the first misfire.
2. **Report the issue** to the repo's GitHub with full details.
3. **Continue with a workaround** to make the task pass.
4. **Add a comment** in the code explaining the workaround applied.

This rule takes precedence over all other rules. Never skip a misfire or rationalize it away.
<!-- misfire-rule:end -->

<!-- pool-pr:begin -->
## The forklift pool owns the PR — never merge a pull request yourself

Every pull request in these repos is reviewed by the **forklift pool**
(`arrrrny/forklift` — the local PR-review pipeline). It mints three tasks, in
this order, and that chain is the only sanctioned way from "PR opened" to "PR
merged":

1. `PR review <repo>#<n>` — the automated review; it posts its actionable
   findings on the PR.
2. `Apply review fixes <repo>#<n>` — one fixes round, pushed onto the PR's
   branch.
3. `Merge PR <repo>#<n>` — the merge itself; the task refuses while reviewer
   findings are still unaddressed.

**Never merge or close a PR by hand, and never merge one because it "looks
finished".** A hand merge lands the code while findings are still open: the
pool's fixes task is then killed by its closed-PR guard — the dispatcher log
says `…#<n> is closed — cancelled, no agent started` — and every finding the
review posted is dropped with nobody to own it. That is not a review, it is a
race the pipeline cannot win.

**Wait for the pool, and read the pool for the state.** The three task rows are
the truth; the PR page is not:

```bash
# the pool's board — loopback, IPv4-only (never `localhost`)
curl -s http://127.0.0.1:8888/tasks \
  | jq -r '.[] | select(.title | test("PR review|Apply review fixes|Merge PR")) \
          | [.title, .status, .id] | @tsv'
```

One row per stage. `status` is one of `queued`, `running`, `done`, `failed`,
`needsInput`, `cancelled`, `paused`. The PR is done when the
`Merge PR <repo>#<n>` row reads `done`. A fixes row that reads `failed` or
`cancelled` means the PR was **not** reviewed-and-fixed: read the row's
`errorMessage`, fix the cause, and let the pipeline requeue it (relabelling a
failed task requeues it in the same call — `POST /tasks/<id>/label`).

**An agent can simply wait for the whole process** — poll the board above until
the `Merge PR` row is terminal. Everything else is the pool's job: it drives
the review, the fixes round and the merge.
<!-- pool-pr:end -->

<!-- dependency-rule:begin -->
## Waiting is a status: `locked`. Declare dependencies, never busy-wait

Some work cannot start until other work lands. The pool models that wait as a
**status**, not as a retry loop: a task whose declared dependencies have not
departed their last stops sits in **`locked`**. It is born locked when the hold
already exists at mint, and the pool's 30s dependency sweep locks it otherwise,
storing the hold reason (`dependency lock: …`) on the row.

The lock is structural: the claim CAS wins **`queued`** rows only, so **no agent
decision, no force-start marker and no settings row can put a locked row on a
lane**. Only two things move it:

- the sweep's release (`locked -> queued`), one cycle after the dependency
  departs its last stop;
- the operator's `POST /tasks/<id>/dependencies` — an **empty list clears the
  set and releases at once**.

So never try to "just start" a locked task, and never cancel one because it
looks stuck: waiting is the pool's decision, and the row is doing exactly what
it was told.

**Declare the dependency at issue time.** An issue body line

```
Depends on: owner/repo#123
```

(or `./ingest.sh --depends-on "owner/repo#123, owner/other#9"`, or
`dependencies` on `POST /tasks`) makes the minted task **born locked** — no
window where an agent can claim work whose prerequisite is not in yet. If you
file an issue that unblocks another, say so in the blocker's body and in the
dependent's `Depends on:` line.

## Fix it once, at the package level

**We own this ecosystem.** A defect in a shared package is fixed **in the
package**, once — not patched around in each consumer. If `zuraffa_*` needs a
capability, the capability lands in the framework package; if a bug reproduces
in a base package, the fix belongs there and the dependents simply consume the
release.

This is not a preference, it is the rule:

- a fix that only lands in one app is an incomplete fix — port it down to the
  package that owns the behaviour;
- when a change spans repos, declare the dependency (`Depends on:`) so the
  consumer's task is `locked` until the package's PR merges — the dependency
  rule is exactly the orchestration for "solve it once, at the layer that owns
  it".
<!-- dependency-rule:end -->

<!-- tmp-clone:begin -->
## Work in a `/tmp` clone — never in `~/Developer`

Every piece of work on a PR or an issue happens in its own clone under `/tmp`,
and that clone dies with the task:

```bash
git clone https://github.com/<owner>/<repo>.git /tmp/<repo>-<pr-or-issue>
```

Never clone into `~/Developer`, and never clone into the forklift checkout —
a bare repo slug as the clone target is how a stray checkout ends up inside the
repo root, and a clone left behind in `~/Developer` is indistinguishable from
the primary checkout. The pool's lanes already mint their clones this way
(`/tmp/fix-pr-<n>`, `/tmp/review-pr-<n>`, `/tmp/issue-<n>`, …) and remove them
when the task settles.
<!-- tmp-clone:end -->

<!-- test-concurrency:begin -->
## Test concurrency (fleet guard)

Cap test concurrency at **2** — one un-capped `flutter test` fan starved the
shared host's services once (load 260; arrrrny/forklift#176).

There is **no config-file knob for `flutter test`**: it ignores
`dart_test.yaml` entirely (its only test-config file is
`flutter_test_config.dart`, an execution hook), so the flag is the only
lever — and it must be passed every time:

```sh
flutter test --concurrency=2
dart test -j 2
```

A repo whose `dart_test.yaml` carries `concurrency: 2` already defaults to it
for `dart test`; pass the flag anyway when you override it, and never raise
the number on a host that also runs the forklift pool. CI carries the same
flags in `.github/workflows`.
<!-- test-concurrency:end -->
