# oiax-sample

A branch-per-environment GitOps **fixture** repository for exercising
[oiax](https://github.com/skaphos/oiax) — the declarative Git branch
promotion reconciler.

> This is not a real application. It is a controlled test bed: the
> long-lived environment branches are pre-seeded with known divergence
> so you can run `oiax plan` / `oiax reconcile` and check that it
> proposes the right **promotion** (progression) and **backflow**
> (backporting) pull requests. See [SCENARIOS.md](SCENARIOS.md) for the
> exact seeded state and expected output.

## Branch model

The promotion graph declared in [`.oiax.yaml`](.oiax.yaml):

```
development ──▶ test ──▶ qa ──▶ production-stage-1 ──▶ main
   (source)                                          (terminal)
```

| Branch               | Role     | Notes                                        |
| -------------------- | -------- | -------------------------------------------- |
| `development`        | source   | where net-new change enters                  |
| `test`               | —        | promotion target; `drift: expected`          |
| `qa`                 | —        | promotion target; `drift: expected`          |
| `production-stage-1` | —        | promotion target; backflow source            |
| `main`               | terminal | production; backflow source; default         |

Backflow returns hotfixes applied on `production-stage-1` or `main`
back to `development` via `cherry-pick`, then they promote forward
normally.

### Drift on transit branches (recommended)

`test` and `qa` are declared **`drift: expected`**. This is a deliberate
recommendation for pure *transit* branches — branches that only ever
receive content through promotion — and it is worth understanding before
you adapt this fixture to a real graph.

oiax decides whether a destination has diverged **by reachability**
(`git rev-list <source>..<destination>`), not by content. When a
promotion PR is merged with **"Squash and merge"** or **"Create a merge
commit"** — GitHub's two default buttons — the destination gains a new
commit that exists on no upstream branch: the squash commit, or the merge
node. That commit's *content* is fully represented upstream, but as a
commit it is unique to the destination, so oiax reports it:

```
report  development -> test (1): test has 1 commits not represented in development
converged with reported divergence      # reconcile exits 3
```

Only a **fast-forward** promotion leaves the destination a strict subset
with nothing unique (`rev-list` empty). Since GitHub's standard PR merge
buttons do not fast-forward, a transit branch inevitably accumulates this
benign promotion residue. `drift: expected` tells oiax to acknowledge
downstream-only content on that branch silently, so the residue does not
trip a `reconcile` exit 3 on every cycle.

Where **not** to use it:

- **Backflow sources** (`production-stage-1`, `main`) must stay
  drift-forbidden (the default). Their downstream-only content is a
  hotfix to be *returned* by backflow, not ignored — oiax's validator
  rejects `drift: expected` on a backflow source.
- If you can enforce **fast-forward-only promotions** (via the API, the
  CLI, or a merge queue), prefer that and keep every branch
  drift-forbidden: the graph stays clean and genuine accidental drift on
  a transit branch is still caught. `drift: expected` is the pragmatic
  choice when promotions merge as squash/merge commits on GitHub.

See the upstream [drift policy
guide](https://github.com/skaphos/oiax/blob/main/docs/guides/promotion-graphs.md#drift-policy).

## Seeded divergence (at a glance)

- **Progression:** `development` is one commit ahead of `test` (a
  feature bump). Every downstream branch is still at the base, so the
  `development → test` edge needs a promotion request; each subsequent
  edge lights up as you merge.
- **Backporting:** `main` carries a hotfix that exists on no upstream
  branch, so the `main` backflow source needs a `cherry-pick` request
  back to `development`.

The two changes touch disjoint files (`app/deployment.yaml` vs.
`app/config.yaml`) so the backflow cherry-pick applies without conflict.

## Running oiax against this repo

Clone with every environment branch present, then point oiax at it:

```bash
git clone https://github.com/skaphos/oiax-sample.git
cd oiax-sample
git fetch origin '+refs/heads/*:refs/remotes/origin/*'   # all env branches

oiax validate     # graph is well-formed
oiax graph        # show the topology
oiax plan         # the dry run: promotion + backflow actions
oiax reconcile    # plan, then create the managed PRs
```

`reconcile` (given a forge token via `GITHUB_TOKEN`) opens the managed
pull requests directly on this repo. To reset the fixture, re-run
[`scripts/seed.sh`](scripts/seed.sh) or re-clone.

Install the CLI (needs Go 1.26+):

```bash
go install github.com/skaphos/oiax/cmd/oiax@latest
```

## In-repo automation

[`.github/workflows/oiax.yml`](.github/workflows/oiax.yml) runs
`skaphos/oiax@v1` on pushes to environment branches, promotion-PR close,
an hourly schedule, and manual dispatch. Manual runs default to
`mode: plan` so you can inspect the fixture dry-run from the Actions UI.

For unattended production under branch protection, wire a GitHub App
installation token into the Action's `token` input — PRs created with the
default `GITHUB_TOKEN` do not start `on: pull_request` checks. See the
[tokens guide](https://github.com/skaphos/oiax/blob/main/docs/guides/tokens.md).

## Resetting

Everything here is disposable. `scripts/seed.sh` rebuilds all branches
and force-pushes them, restoring the exact seeded state described in
[SCENARIOS.md](SCENARIOS.md).
