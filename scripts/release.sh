#!/usr/bin/env bash
# Cut a release: bump the Helm chart version in lockstep with the release
# tag, run the quality gates, then commit, tag and push. The GitHub release
# itself is created by CI (.github/workflows/release.yml) on the tag push.
#
# Usage: scripts/release.sh X.Y.Z
#
# Env flags:
#   DRY_RUN=1        Run all checks/gates, show the Chart.yaml bump as a
#                     diff, then restore the file and stop before
#                     commit/tag/push.
#   RELEASE_BRANCH    Branch the release must be cut from (default: main).
set -euo pipefail

CHART_FILE="deploy/helm/algalon/Chart.yaml"
RELEASE_BRANCH="${RELEASE_BRANCH:-main}"
DRY_RUN="${DRY_RUN:-0}"

die() {
	echo "error: $*" >&2
	exit 1
}

[ "$#" -eq 1 ] || die "usage: scripts/release.sh X.Y.Z"
VERSION="$1"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
	|| die "version '$VERSION' must match X.Y.Z (e.g. 0.5.0)"

TAG="v${VERSION}"

# Run from the repo root regardless of the caller's cwd.
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

[ -f "$CHART_FILE" ] || die "chart file not found: $CHART_FILE"
command -v gh >/dev/null 2>&1 || die "gh CLI is required but not found on PATH"

current_branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$current_branch" = "$RELEASE_BRANCH" ] \
	|| die "must be on branch '$RELEASE_BRANCH' (currently on '$current_branch')"

[ -z "$(git status --porcelain)" ] \
	|| die "working tree is not clean; commit or stash changes first"

echo "==> Fetching origin..."
git fetch origin

local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse "origin/${RELEASE_BRANCH}")"
[ "$local_head" = "$remote_head" ] \
	|| die "HEAD ($local_head) is not in sync with origin/${RELEASE_BRANCH} ($remote_head); pull/push first"

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
	die "tag '${TAG}' already exists locally"
fi
if git ls-remote --tags origin "refs/tags/${TAG}" | grep -q "${TAG}"; then
	die "tag '${TAG}' already exists on origin"
fi

echo "==> Bumping ${CHART_FILE} to ${VERSION}..."
sed -i.bak \
	-e "s/^version: .*/version: ${VERSION}/" \
	-e "s/^appVersion: .*/appVersion: \"${VERSION}\"/" \
	"$CHART_FILE"
rm -f "${CHART_FILE}.bak"

echo "==> Running quality gates (rules-test, helm-validate, dashboards-validate)..."
make rules-test helm-validate dashboards-validate

if [ "$DRY_RUN" = "1" ]; then
	echo "==> DRY_RUN=1: Chart.yaml bump (not committed):"
	git --no-pager diff -- "$CHART_FILE"
	echo "==> Restoring ${CHART_FILE}..."
	git checkout -- "$CHART_FILE"
	echo "==> Dry run complete; no commit/tag/push performed."
	exit 0
fi

echo "==> Committing chart bump..."
git add "$CHART_FILE"
git commit -m "chore: release v${VERSION}"

echo "==> Creating annotated tag ${TAG}..."
git tag -a "$TAG" -m "${TAG}"

echo "==> Pushing ${RELEASE_BRANCH} and ${TAG}..."
git push origin "$RELEASE_BRANCH"
git push origin "$TAG"

repo_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")"
if [ -n "$repo_slug" ]; then
	echo "==> Pushed. CI (.github/workflows/release.yml) will create the GitHub release at:"
	echo "    https://github.com/${repo_slug}/releases/tag/${TAG}"
else
	echo "==> Pushed. CI (.github/workflows/release.yml) will create the GitHub release for tag ${TAG}."
fi
