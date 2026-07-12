#!/usr/bin/env bash
#
# Rebuild the seeded fixture state for oiax-sample.
#
# Restores all five environment branches to the exact divergence
# described in SCENARIOS.md and force-pushes them. This repository is a
# disposable test bed — force-pushing the environment branches (main
# included) back to their seeded state is the intended workflow.
#
# Usage (from a clone of this repo):
#   scripts/seed.sh
#   OIAX_SAMPLE_REMOTE=fork scripts/seed.sh   # push somewhere else
#
set -euo pipefail

REMOTE="${OIAX_SAMPLE_REMOTE:-origin}"
BRANCHES=(development test qa production-stage-1 main)

# The shared ancestor every branch is rebuilt from is tagged fixture-base.
git fetch --tags --quiet "$REMOTE"
BASE="$(git rev-parse fixture-base^{commit})"

# Detach first so we can force-update whichever branch is checked out,
# then point every environment branch back at the base.
git switch -q --detach "$BASE"
for b in "${BRANCHES[@]}"; do
  git branch -f "$b" "$BASE"
done

# --- Scenario 1: progression (promotion) -------------------------------
# development gains one feature commit that no other branch has.
git switch -C development "$BASE" >/dev/null
sed -i 's#sample-app:1\.0\.0#sample-app:1.1.0#' app/deployment.yaml
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
sed -i \
  -e 's/^timeoutSeconds: 30$/timeoutSeconds: 120/' \
  -e 's/^logLevel: info$/logLevel: warn/' \
  app/config.yaml
git add -A
git commit -s -q -m "fix(config): raise request timeout to 120s (production hotfix)"

git switch -q main
git push --force "$REMOTE" "${BRANCHES[@]}"

echo "Fixture reset. Seeded divergence restored on: ${BRANCHES[*]}"
