#!/bin/zsh
# Promotes main to a release: turns its current state into a stable version.
#   scripts/release.sh                 release the version main is on (scripts/version.sh), e.g. 0.2.0
#   scripts/release.sh 0.2.0-beta.1    a pre-release of that version: tag only, the changelog stays as is
#   scripts/release.sh --push          the same, and push main and the tag (starts the release build)
# For a stable version it moves the Unreleased changelog entries under the new version, commits "Release X.Y.Z",
# tags vX.Y.Z, then starts the next minor version on main ("Start X.Y+1.0"), the version being worked on next.
# For a patch release instead, run `scripts/version.sh set X.Y.Z` and commit before running this.
set -euo pipefail
cd "$(dirname "$0")/.."

PUSH=false
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --push) PUSH=true ;;
    -*) echo "unknown option $arg" >&2; exit 1 ;;
    *) VERSION="$arg" ;;
  esac
done
CURRENT="$(scripts/version.sh)"
VERSION="${VERSION:-$CURRENT}"
TAG="v$VERSION"
CHANGELOG=docs/CHANGELOG.md

fail() { echo "error: $*" >&2; exit 1; }
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' ]] || fail "$VERSION isn't a version like 0.2.0 or 0.2.0-beta.1"
[[ "${VERSION%%-*}" == "$CURRENT" ]] || fail "main is on $CURRENT; run 'scripts/version.sh set ${VERSION%%-*}' and commit first"
[[ "$(git branch --show-current)" == main ]] || fail "releases are cut from main"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "commit or stash your changes first"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists"
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main differs from origin/main; pull or push first"

if [[ "$VERSION" == *-* ]]; then
  git tag -a "$TAG" -m "BetterActivityMonitor $VERSION"
  echo "Tagged $TAG (pre-release)."
else
  # The lines between "## [Unreleased]" and the next heading.
  ENTRIES="$(awk '/^## \[Unreleased\]/ {on=1; next} /^## / && on {exit} on' "$CHANGELOG" | grep -v '^[[:space:]]*$' || true)"
  [[ -n "$ENTRIES" ]] || fail "no entries under ## [Unreleased] in $CHANGELOG"
  awk -v v="$VERSION" -v d="$(date +%Y-%m-%d)" '{print} /^## \[Unreleased\]/ {print ""; print "## [" v "] - " d}' \
    "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"
  git commit -q -m "Release $VERSION" -- "$CHANGELOG"
  git tag -a "$TAG" -m "BetterActivityMonitor $VERSION"

  IFS=. read -r MAJOR MINOR _ <<< "$VERSION"
  NEXT="$MAJOR.$((MINOR + 1)).0"
  scripts/version.sh set "$NEXT" >/dev/null
  git commit -q -m "Start $NEXT" -- BetterActivityMonitor.xcodeproj/project.pbxproj
  echo "Released $VERSION as $TAG; main is now on $NEXT."
fi

if $PUSH; then
  git push origin main "$TAG"
  echo "Pushed. The release build runs at https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo '<owner>/<repo>')/actions"
else
  echo "Check with 'git log --oneline -3', then: git push origin main $TAG"
fi
