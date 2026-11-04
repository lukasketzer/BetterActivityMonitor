#!/bin/zsh
# Prints the app's version. The one source of truth is MARKETING_VERSION in the Xcode project: on main it is
# the version being worked on (the next release).
#   scripts/version.sh            0.2.0                    the marketing version
#   scripts/version.sh build      412                      build number: commits on HEAD, so it only goes up
#   scripts/version.sh set 0.3.0  sets MARKETING_VERSION
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT=BetterActivityMonitor.xcodeproj/project.pbxproj

marketing() {
  local versions=(${(u)${(f)"$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PROJECT")"}})
  (( ${#versions} == 1 )) || { echo "expected one MARKETING_VERSION in $PROJECT, found: ${versions[*]:-none}" >&2; exit 1; }
  echo "${versions[1]}"
}

case "${1:-}" in
  "") marketing ;;
  build) git rev-list --count HEAD ;;
  set)
    [[ "${2:-}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "usage: $0 set <major.minor.patch>" >&2; exit 1; }
    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $2;/" "$PROJECT"
    marketing ;;
  *) echo "usage: $0 [build|set <version>]" >&2; exit 1 ;;
esac
