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

| Branch               | Role     | Notes                                   |
| -------------------- | -------- | --------------------------------------- |
| `development`        | source   | where net-new change enters             |
| `test`               | —        | promotion target                        |
| `qa`                 | —        | promotion target                        |
| `production-stage-1` | —        | promotion target; backflow source       |
| `main`               | terminal | production; backflow source; default    |

Backflow returns hotfixes applied on `production-stage-1` or `main`
back to `development` via `cherry-pick`, then they promote forward
normally.

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

`reconcile` (once oiax is released and given a forge token) opens the
managed pull requests directly on this repo. To reset the fixture,
re-run [`scripts/seed.sh`](scripts/seed.sh) or re-clone.

## In-repo automation

[`.github/workflows/oiax.yml`](.github/workflows/oiax.yml) ships the
reconcile workflow as **manual-dispatch only** so it can't fail before
oiax has a tagged release. Enable the event triggers commented inside it
to run oiax the way a production repo would.

## Resetting

Everything here is disposable. `scripts/seed.sh` rebuilds all branches
and force-pushes them, restoring the exact seeded state described in
[SCENARIOS.md](SCENARIOS.md).
