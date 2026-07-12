# Seeded scenarios

Every environment branch starts from an identical **base** commit (the
shared ancestor). Two changes are then layered on to create the two
divergences oiax is meant to reconcile. Nothing else differs between
branches, so oiax's proposed actions are fully predictable.

```
base ─┬─────────────────────────────▶ test, qa, production-stage-1   (unchanged)
      │
      ├─▶ feat: analytics dashboard, bump 1.1.0 ─▶ development
      │
      └─▶ fix: raise timeout to 120s (hotfix) ──▶ main
```

## Scenario 1 — Progression (promotion)

**Seed:** `development` has one commit that no other branch has —
`feat(app): add analytics dashboard and bump to 1.1.0`
(edits `app/deployment.yaml`, adds `app/features/analytics-dashboard.yaml`).
`test`, `qa`, and `production-stage-1` are all still at the base.

**Expected oiax behaviour:**

| Edge                               | Ladder verdict      | Action                          |
| ---------------------------------- | ------------------- | ------------------------------- |
| `development → test`               | promotion required  | open one managed promotion PR   |
| `test → qa`                        | in sync             | none                            |
| `qa → production-stage-1`          | in sync             | none                            |
| `production-stage-1 → main`        | destination ahead   | none forward (see Scenario 2)   |

Merge the `development → test` PR and re-run: `test` now leads `qa`, so
the `test → qa` edge becomes *promotion required*. Walking the merges
carries the change all the way to `main` — that is the progression the
fixture exists to demonstrate.

## Scenario 2 — Backporting (backflow)

**Seed:** `main` has one commit that exists on no upstream branch —
`fix(config): raise request timeout to 120s (production hotfix)`
(edits `app/config.yaml` only). This models a hotfix applied directly to
production.

**Expected oiax behaviour:** `main` is a configured backflow source and
is *destination ahead* of `production-stage-1`, so oiax should:

1. create `oiax/backflow/main-to-development/<main-head-short-sha>`
   from `development`,
2. `git cherry-pick -x` the hotfix commit onto it,
3. open one managed **backflow** PR from that branch to `development`.

Because the hotfix touches `app/config.yaml` and the Scenario 1 feature
touches `app/deployment.yaml` + `app/features/`, the cherry-pick applies
cleanly. After the backflow PR merges into `development`, the hotfix
promotes forward through the graph like any other change.

> `production-stage-1` is also declared a backflow source but carries no
> unique commits, so it produces no backflow action in the seeded state.
> Add a commit there to exercise a second backflow origin.

## Rebuilding this state

`scripts/seed.sh` recreates all five branches from scratch and
force-pushes them, restoring exactly the divergence above.
