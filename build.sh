#!/usr/bin/env bash
set -euo pipefail

IMAGE="hvetsa"
VERSION_FILE="$(dirname "$0")/VERSION"

# ─── Helpers ──────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build the $IMAGE Docker image.

Options:
  -v, --version  VERSION   Override version (default: contents of VERSION file)
                           Format: MAJOR.MINOR.PATCH  e.g. 1.2.3
  --bump major|minor|patch Auto-increment the chosen segment and save to VERSION
  --no-cache               Pass --no-cache to docker build
  -h, --help               Show this help

Examples:
  $(basename "$0")                   # build with current VERSION
  $(basename "$0") -v 2.0.0          # build with explicit version
  $(basename "$0") --bump minor       # bump 1.0.0 → 1.1.0, then build
EOF
}

semver_bump() {
  local version="$1" segment="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  case "$segment" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) echo "ERROR: --bump must be major, minor, or patch" >&2; exit 1 ;;
  esac
  echo "${major}.${minor}.${patch}"
}

validate_semver() {
  if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: '$1' is not valid semantic versioning (expected MAJOR.MINOR.PATCH)" >&2
    exit 1
  fi
}

# ─── Parse arguments ──────────────────────────────────────────────────────────
VERSION=""
BUMP=""
NO_CACHE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version) VERSION="$2"; shift 2 ;;
    --bump)       BUMP="$2";    shift 2 ;;
    --no-cache)   NO_CACHE="--no-cache"; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# ─── Resolve version ──────────────────────────────────────────────────────────
if [[ -z "$VERSION" ]]; then
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "ERROR: VERSION file not found at $VERSION_FILE" >&2; exit 1
  fi
  VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
fi

validate_semver "$VERSION"

if [[ -n "$BUMP" ]]; then
  VERSION=$(semver_bump "$VERSION" "$BUMP")
  echo "$VERSION" > "$VERSION_FILE"
  echo "Bumped version → $VERSION (saved to VERSION)"
fi

IFS='.' read -r MAJOR MINOR _PATCH <<< "$VERSION"

# ─── Build ────────────────────────────────────────────────────────────────────
echo "Building $IMAGE:$VERSION ..."

docker build $NO_CACHE \
  --label "org.opencontainers.image.version=$VERSION" \
  --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t "$IMAGE:$VERSION"      \
  -t "$IMAGE:$MAJOR.$MINOR" \
  -t "$IMAGE:$MAJOR"        \
  -t "$IMAGE:latest"        \
  "$(dirname "$0")"

echo ""
echo "Built tags:"
echo "  $IMAGE:$VERSION"
echo "  $IMAGE:$MAJOR.$MINOR"
echo "  $IMAGE:$MAJOR"
echo "  $IMAGE:latest"
