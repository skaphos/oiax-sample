#!/usr/bin/env bash
#
# Rebuild the seeded fixture state for oiax-sample.
#
# Restores all five environment branches to the exact divergence described
# in SCENARIOS.md and force-pushes them. This repository is a disposable
# test bed — force-pushing the environment branches (main included) back to
# their seeded state is the intended workflow.
#
# The seed CAPTURES THE CURRENT SETUP. Every environment branch is built
# from one shared base commit made of:
#
#   * the pristine 1.0.0 application skeleton, taken from the fixture-base
#     tag (this is what the two scenarios diverge from), and
#   * the repo-management files — the oiax config, the CI workflow, the
#     docs, and this script — taken from the checkout you run this from.
#
# Because every branch starts from that identical base, the oiax config and
# CI files never differ between branches, so they are never treated as
# promotable or backflow content. Only the two scenario commits below
# diverge. Run this from an up-to-date `main` so the captured setup is the
# canonical one; running it from a stale checkout would seed a stale setup.
#
# Usage (from a clone of this repo, clean working tree):
#   scripts/seed.sh
#   OIAX_SAMPLE_REMOTE=fork scripts/seed.sh   # push somewhere else
#   OIAX_SAMPLE_KEEP_REQUESTS=1 scripts/seed.sh   # keep the previous cycle's
#                                                 # oiax requests and branches
#
# In-place edits use `perl -pi` rather than `sed -i`: GNU and BSD sed disagree
# on whether -i takes a suffix argument, so `sed -i 's/…/…/' file` fails on
# macOS. This script is a local workstation tool and must run on both.
set -euo pipefail

REMOTE="${OIAX_SAMPLE_REMOTE:-origin}"
BRANCHES=(development test qa production-stage-1 main)

# Repo-management files that must stay IDENTICAL on every environment branch.
# Captured from the current checkout — NOT from fixture-base — so re-seeding
# never reverts a setup change (drift policy, App-token workflow, docs …).
SETUP_PATHS=(.oiax.yaml .github README.md SCENARIOS.md scripts)

# owner/name for `gh --repo`, derived from the push remote so that seeding a
# fork cleans up the fork's forge rather than upstream's.
remote_slug() {
  local url
  url="$(git remote get-url "$REMOTE" 2>/dev/null)" || return 1
  url="${url%.git}"
  case "$url" in
  *github.com[:/]*)
    url="${url#*github.com}"
    printf '%s\n' "${url#[:/]}"
    ;;
  *) return 1 ;;
  esac
}

# Clear what the previous cycle left on the forge.
#
# A reset rewrites every environment branch, so the requests oiax opened last
# time reference commits this run orphans, and each backflow branch is named
# after the old `main` head — the next run derives a new name and never
# reclaims the old one. Left alone, every reset strands one more request and
# one more oiax/* branch, and the next reconcile *updates* a leftover
# promotion request instead of creating one, which is not the behaviour
# SCENARIOS.md documents.
#
# Closing cannot destroy real promotion provenance: oiax's baseline rung
# reads MERGED requests only, and a closed-unmerged request has no merged_at,
# so it is skipped during discovery.
#
# Best-effort. Without an authenticated gh the fixture still seeds correctly;
# it just keeps the stale requests.
reset_forge() {
  if [ -n "${OIAX_SAMPLE_KEEP_REQUESTS:-}" ]; then
    echo "keeping the previous cycle's oiax requests and branches"
    return 0
  fi

  local repo
  repo="$(remote_slug)" || {
    echo "note: $REMOTE is not a GitHub remote; skipping forge cleanup" >&2
    return 0
  }

  if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
    echo "note: gh unavailable or unauthenticated; stale oiax requests will remain" >&2
    return 0
  fi

  # A managed request carries an HTML-comment marker whose content has a line
  # that is exactly `oiax:`. Match on that, not on the title — a human can
  # retitle a PR, but editing the marker block is what oiax tells them not to do.
  local n
  while read -r n; do
    [ -n "$n" ] || continue
    echo "closing stale managed request #${n}"
    gh pr close "$n" --repo "$repo" \
      --comment "Superseded by a fixture reset (\`scripts/seed.sh\`): the commits this request referenced no longer exist." \
      >/dev/null || true
  done < <(gh pr list --repo "$repo" --state open --limit 100 --json number,body \
    --jq '.[] | select(.body | test("(?m)^oiax:$")) | .number')

  # Delete only the branches oiax itself created. The environment branches are
  # rebuilt below and must never be deleted here. One push per ref: bash 3.2
  # (still the /bin/bash on macOS) treats ${#arr[@]} on an empty array as an
  # unbound variable under `set -u`, so this avoids accumulating into one.
  local sha ref
  while read -r sha ref; do
    [ -n "${ref:-}" ] || continue
    echo "deleting ${ref#refs/heads/}"
    git push --quiet --delete "$REMOTE" "$ref" || true
  done < <(git ls-remote --heads "$REMOTE" 'refs/heads/oiax/*')
}

# Capture the setup commit before moving HEAD.
SETUP_REF="$(git rev-parse HEAD)"

# The pristine application skeleton (deployment 1.0.0, config 30s/info) comes
# from the fixture-base tag; the scenarios diverge from it.
git fetch --tags --quiet "$REMOTE"
APP_BASE="$(git rev-parse fixture-base^{commit})"

# Build the shared base: detach onto the pristine app skeleton, overlay the
# captured setup files on top of it, and commit. Every branch starts here.
git switch -q --detach "$APP_BASE"
git checkout -q "$SETUP_REF" -- "${SETUP_PATHS[@]}"
git add -A
git commit -s -q -m "chore(fixture): seed base — pristine app skeleton + current setup"
BASE="$(git rev-parse HEAD)"

for b in "${BRANCHES[@]}"; do
  git branch -f "$b" "$BASE"
done

# --- Scenario 1: progression (promotion) -------------------------------
# development gains one feature commit that no other branch has.
git switch -C development "$BASE" >/dev/null
perl -pi -e 's#sample-app:1\.0\.0#sample-app:1.1.0#' app/deployment.yaml
mkdir -p app/features
cat > app/features/analytics-dashboard.yaml <<'YAML'
# Analytics dashboard, introduced in 1.1.0. Enters on development and is
# promoted forward through the graph. See SCENARIOS.md (Scenario 1).
apiVersion: v1
kind: ConfigMap
metadata:
  name: analytics-dashboard
data:
  enabled: "true"
YAML
git add -A
git commit -s -q -m "feat(app): add analytics dashboard and bump to 1.1.0"

# --- Scenario 2: backporting (backflow) --------------------------------
# main gains one hotfix commit that no upstream branch has. It touches a
# file disjoint from Scenario 1 so the backflow cherry-pick applies clean.
git switch -C main "$BASE" >/dev/null
perl -pi \
  -e 's/^timeoutSeconds: 30$/timeoutSeconds: 120/;' \
  -e 's/^logLevel: info$/logLevel: warn/;' \
  app/config.yaml
git add -A
git commit -s -q -m "fix(config): raise request timeout to 120s (production hotfix)"

git switch -q main

# Clear the previous cycle's forge state before the push, so the reconcile
# these pushes trigger starts from nothing and creates both requests fresh.
reset_forge

git push --force "$REMOTE" "${BRANCHES[@]}"

echo "Fixture reset. Seeded divergence restored on: ${BRANCHES[*]}"
