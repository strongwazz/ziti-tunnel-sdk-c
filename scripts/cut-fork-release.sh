#!/usr/bin/env bash
#
# cut-fork-release.sh VERSION
#
# Produce a fork release whose source matches upstream openziti/ziti-tunnel-sdk-c
# at tag vVERSION, with our fork edits (name changes + Windows-only build) applied
# on top, then tag it vVERSION so the build reports the same version as upstream.
#
# Example:
#   scripts/cut-fork-release.sh 1.15.1
#
# What it does:
#   1. fetches upstream tags
#   2. creates branch release-vVERSION from upstream's vVERSION tag
#   3. cherry-picks our fork commits (the patch range below) onto it
#   4. tags it vVERSION and prints the push commands
#
# It deliberately does NOT push or create the GitHub Release for you; review the
# branch first, then run the printed commands. Pushing the tag + publishing the
# GitHub Release is what triggers .github/workflows/fork-release.yml to build and
# upload the Windows artifacts.
#
# Because the fork only adds files upstream doesn't have (fork-release.yml) plus
# a source-only rename, replaying onto an upstream tag does not touch upstream's
# own workflow files and so will not conflict on workflow churn.

set -euo pipefail

VERSION="${1:?usage: cut-fork-release.sh VERSION (e.g. 1.15.1)}"
VERSION="${VERSION#v}"               # tolerate a leading v
TAG="v${VERSION}"
BRANCH="release-${TAG}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"

# The fork patch: every commit on our main that is NOT on upstream/main.
# These get replayed onto the upstream release tag. Override FORK_PATCH_RANGE to
# pin an explicit range if main drifts.
FORK_PATCH_RANGE="${FORK_PATCH_RANGE:-${UPSTREAM_REMOTE}/main..main}"

# --force on tags: a previous run may have force-moved the local ${TAG} onto a
# fork commit, which would otherwise make this fetch fail with "would clobber
# existing tag". We always want upstream's tags to reflect upstream here.
echo "==> fetching ${UPSTREAM_REMOTE} tags"
git fetch --force --tags "${UPSTREAM_REMOTE}"
git fetch origin

# Refuse to run on a dirty tree -- cherry-pick would fail confusingly anyway.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree is dirty. Commit or stash changes first." >&2
  exit 1
fi

# Resolve the upstream release commit NOW, before we touch the local ${TAG} ref.
# The local ${TAG} currently points at upstream's commit; we branch from that
# resolved SHA so we can later force-move ${TAG} onto our release commit without
# losing the base.
UPSTREAM_COMMIT="$(git rev-parse -q --verify "refs/tags/${TAG}^{commit}" || true)"
if [ -z "${UPSTREAM_COMMIT}" ]; then
  echo "ERROR: upstream tag ${TAG} not found. Is ${VERSION} a real openziti release?" >&2
  exit 1
fi

# Clean up any stale state from a previous (failed) run so this is re-runnable.
START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "${START_BRANCH}" = "${BRANCH}" ]; then
  echo "==> currently on ${BRANCH}; switching to main to recreate it"
  git switch main
fi
if git show-ref -q --verify "refs/heads/${BRANCH}"; then
  echo "==> deleting stale ${BRANCH}"
  git branch -D "${BRANCH}"
fi

echo "==> creating ${BRANCH} from upstream ${TAG} (${UPSTREAM_COMMIT})"
git switch -c "${BRANCH}" "${UPSTREAM_COMMIT}"

echo "==> replaying fork commits (${FORK_PATCH_RANGE}) onto ${TAG}"
mapfile -t COMMITS < <(git rev-list --reverse "${FORK_PATCH_RANGE}")
if [ "${#COMMITS[@]}" -eq 0 ]; then
  echo "ERROR: no fork commits found in range ${FORK_PATCH_RANGE}" >&2
  exit 1
fi
git cherry-pick "${COMMITS[@]}"

# Force-move ${TAG} from upstream's commit onto our release commit. Your repo's
# origin/${TAG} (created on push) is what the build and consumers actually use;
# the local upstream tag is overwritten here but is re-fetchable anytime.
echo "==> tagging ${TAG} on fork release commit (was upstream ${UPSTREAM_COMMIT})"
git tag -f -a "${TAG}" -m "EdgeConnect fork of ziti-edge-tunnel ${VERSION}"

cat <<EOF

Done. Branch ${BRANCH} now equals upstream ${TAG} + fork edits, tagged ${TAG}.

Review, then publish:
  git push origin ${BRANCH}
  git push --force origin ${TAG}    # --force: tag may already exist on origin
  gh release create ${TAG} --title ${TAG} --generate-notes

(--force only affects YOUR origin's ${TAG}; upstream is never pushed to.)

Publishing the GitHub Release triggers .github/workflows/fork-release.yml,
which builds the Windows binaries and attaches the .zip artifacts.
EOF
