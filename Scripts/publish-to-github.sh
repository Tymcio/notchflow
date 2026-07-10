#!/usr/bin/env bash
# Publish public-safe NotchFlow source to GitHub.
# See docs/public-repository.md for the full checklist.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REMOTE="${NOTCHFLOW_GITHUB_REMOTE:-origin}"
BRANCH="${NOTCHFLOW_GITHUB_BRANCH:-main}"
CHECK_ONLY=0
COMMIT_MSG=""

usage() {
  cat <<'EOF'
Usage: Scripts/publish-to-github.sh [options]

Validates that only public-safe content is present, runs tests,
then commits and pushes to the public GitHub repository.

Options:
  --check          Validate and test only; do not commit or push
  -m, --message    Commit message (default: auto-generated)
  -h, --help       Show this help

Environment:
  NOTCHFLOW_GITHUB_REMOTE   Git remote name (default: origin)
  NOTCHFLOW_GITHUB_BRANCH   Branch to push (default: main)

See docs/public-repository.md for the release checklist.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    -m|--message) COMMIT_MSG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

echo "==> NotchFlow public repository publish"
echo "    Root:   $ROOT"
echo "    Remote: $REMOTE"
echo "    Branch: $BRANCH"

# --- Forbidden paths (must not be tracked) ---
FORBIDDEN_PATTERNS=(
  '.env'
  'secrets/'
  '*.p12'
  '*.mobileprovision'
  'notary-log.json'
)

echo "==> Checking for forbidden tracked files..."
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: Not a git repository. Run: git init && git remote add origin https://github.com/Tymcio/notchflow.git" >&2
  exit 1
fi

TRACKED_FORBIDDEN=0
for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  if git ls-files -- "$pattern" 2>/dev/null | grep -q .; then
    echo "FORBIDDEN tracked file: $pattern" >&2
    git ls-files -- "$pattern" >&2
    TRACKED_FORBIDDEN=1
  fi
done

# Also check for common secret patterns in tracked files
if git grep -l 'SPARKLE_PRIVATE_ED_KEY=' -- ':!Scripts/publish-to-github.sh' 2>/dev/null | grep -q .; then
  echo "FORBIDDEN: SPARKLE_PRIVATE_ED_KEY value found in tracked files" >&2
  TRACKED_FORBIDDEN=1
fi

if [[ "$TRACKED_FORBIDDEN" -eq 1 ]]; then
  echo "ERROR: Remove forbidden files before publishing. See docs/public-repository.md" >&2
  exit 1
fi
echo "    OK — no forbidden tracked files"

# --- Untracked artifacts warning ---
ARTIFACT_DIRS=('.build' 'build')
for dir in "${ARTIFACT_DIRS[@]}"; do
  if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
    echo "    Note: $dir/ exists locally (gitignored, will not be pushed)"
  fi
done

# --- Tests ---
echo "==> Running tests..."
swift test
echo "    OK — tests passed"

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  echo "==> --check mode: skipping commit and push"
  exit 0
fi

# --- Commit ---
if [[ -z "$COMMIT_MSG" ]]; then
  VERSION="$(grep '^MARKETING_VERSION=' version.env | cut -d= -f2)"
  COMMIT_MSG="chore: sync public repository (v${VERSION})"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "==> Committing changes..."
  git add -A
  git commit -m "$COMMIT_MSG"
else
  echo "==> No local changes to commit"
fi

# --- Push ---
echo "==> Pushing to $REMOTE/$BRANCH..."
git push -u "$REMOTE" "$BRANCH"
echo "==> Done. Public repo updated."
echo "    Next: git tag v<version> && git push $REMOTE v<version>  (for signed release)"
