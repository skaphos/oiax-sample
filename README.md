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

The transit branches `test` and `qa` are declared **`drift: expected`**.
This repo merges promotion PRs by rebase, which leaves a destination-only
commit on each promotion; `drift: expected` acknowledges that residue so
it is not reported as a divergence. Backflow sources (`production-stage-1`,
`main`) stay drift-forbidden — their downstream-only content is a hotfix
to be *returned*, not ignored. For the full explanation and the
fast-forward alternative, see the upstream [transit-branches
guidance](https://github.com/skaphos/oiax/blob/main/docs/guides/promotion-graphs.md#transit-branches-and-merge-residue).

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

Install the CLI from the [v2.0.0
release](https://github.com/skaphos/oiax/releases/tag/v2.0.0) and verify it
against that release's `checksums.txt`:

```bash
OIAX_VERSION=2.0.0
OS=$(uname -s | tr '[:upper:]' '[:lower:]')       # linux · darwin
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
BASE=https://github.com/skaphos/oiax/releases/download/v${OIAX_VERSION}

curl -fsSLO "${BASE}/oiax_${OIAX_VERSION}_${OS}_${ARCH}.tar.gz"
curl -fsSLO "${BASE}/checksums.txt"
shasum -a 256 --ignore-missing -c checksums.txt
tar -xzf "oiax_${OIAX_VERSION}_${OS}_${ARCH}.tar.gz" oiax
./oiax version    # must report 2.0.0
```

`go install` is not a route to 2.x: oiax's module path is still
`github.com/skaphos/oiax` (no `/v2` suffix), so the Go proxy ignores the v2
tags and `@latest` resolves to **v1.3.0**. Use the release archive.

Automation runs on Linux under v2; the darwin binary above is a best-effort
local tool for driving this fixture from a workstation.

## In-repo automation

[`.github/workflows/oiax.yml`](.github/workflows/oiax.yml) runs
`skaphos/oiax@v2` on pushes to environment branches, promotion-PR close,
an hourly schedule, and manual dispatch. Manual runs default to
`mode: plan` so you can inspect the fixture dry-run from the Actions UI.

The workflow also fetches `refs/pull/*/head` before running oiax. That step
exists only because this repo is reset by force-push: an already-merged
managed promotion request records the `sourceHead` it promoted, and a reset
orphans that commit. Oiax resolves the recorded head when it evaluates the
edge and exits 1 if it cannot — on oiax 1.x and 2.x alike. GitHub keeps the
commit under `refs/pull/<n>/head`, so fetching those refs is enough. A
repository that never rewrites a promotion source will never hit this.

For unattended production under branch protection, wire a GitHub App
installation token into the Action's `token` input — PRs created with the
default `GITHUB_TOKEN` do not start `on: pull_request` checks. See the
[tokens guide](https://github.com/skaphos/oiax/blob/main/docs/guides/tokens.md).

## Resetting

Everything here is disposable. `scripts/seed.sh` rebuilds all branches
and force-pushes them, restoring the exact seeded state described in
[SCENARIOS.md](SCENARIOS.md).
