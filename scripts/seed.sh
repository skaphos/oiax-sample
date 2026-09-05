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
git push --force "$REMOTE" "${BRANCHES[@]}"

echo "Fixture reset. Seeded divergence restored on: ${BRANCHES[*]}"
