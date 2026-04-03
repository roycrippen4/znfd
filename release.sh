#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
BRANCH="master"
REMOTE="origin"
FILE="build.zig.zon"
TAG_PREFIX="v"
TAG_MSG_PREFIX="Release v"
DRY_RUN=false

# --- Helpers ---
die() {
  echo "Error: $*" >&2
  exit 1
}
info() { echo "Info: $*"; }
warn() { echo "Warning: $*"; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

# Run a command only if not in dry-run mode
run() {
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# --- Initialization ---
need git
need sed
need zig

# Handle flags
for arg in "$@"; do
  case $arg in
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  *) break ;;
  esac
done

# --- Preconditions ---
[ -f "$FILE" ] || die "Missing $FILE"

# 1. Ensure we are on the correct branch
cur_branch="$(git branch --show-current)"
[ "$cur_branch" = "$BRANCH" ] || die "Must be on $BRANCH (currently: $cur_branch)"

# 2. Ensure working tree is clean
[ -z "$(git status --porcelain)" ] || die "Working tree must be clean. Commit your changes first."

# 3. Sync with remote and check state
info "Fetching from $REMOTE..."
git fetch "$REMOTE" --tags >/dev/null 2>&1 || die "Failed to fetch from $REMOTE"

behind="$(git rev-list --count "$BRANCH..$REMOTE/$BRANCH")"
if [ "$behind" -gt 0 ]; then
  die "Local branch is behind $REMOTE/$BRANCH by $behind commits. Pull first."
fi

# 4. Get current version from file
file_ver="$(grep -m1 '\.version' "$FILE" | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "$file_ver" ] || die "Could not parse .version from $FILE"
info "Current file version: $file_ver"

# 5. Get latest tag from remote
latest_tag="$(git tag -l "${TAG_PREFIX}[0-9]*" --sort=-v:refname --merged "$REMOTE/$BRANCH" | head -n1 || true)"

if [ -z "$latest_tag" ]; then
  warn "No existing tags found. Starting fresh."
  latest_ver="0.0.0"
else
  latest_ver="${latest_tag#${TAG_PREFIX}}"
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "$latest_tag"^{commit} 2>/dev/null)" ]; then
    die "Current HEAD is already tagged as $latest_tag"
  fi
fi

# --- Version Logic ---
base_ver="$(echo "$latest_ver" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
major="${base_ver%%.*}"
rest="${base_ver#*.}"
minor="${rest%%.*}"
patch="${base_ver##*.}"

inc_patch="$major.$minor.$((patch + 1))"
inc_minor="$major.$((minor + 1)).0"
inc_major="$((major + 1)).0.0"

# --- Interactive Selection ---
pick_version() {
  local prompt="Select version (Current: $file_ver, Latest Tag: $latest_ver):"

  if command -v fzf >/dev/null 2>&1; then
    printf "patch (%s)\nminor (%s)\nmajor (%s)\ncustom\n" "$inc_patch" "$inc_minor" "$inc_major" |
      fzf --prompt="$prompt " --height=10 --border --no-multi --header="Enter to select / Esc to cancel" |
      sed -n 's/.*(\(.*\)).*/\1/p'
  else
    echo "$prompt"
    echo "1) patch ($inc_patch)  2) minor ($inc_minor)  3) major ($inc_major)"
    read -r -p "Choice [1-3]: " choice
    case "${choice}" in
    1) echo "$inc_patch" ;;
    2) echo "$inc_minor" ;;
    3) echo "$inc_major" ;;
    *) die "Invalid or cancelled" ;;
    esac
  fi
}

new_ver="$(pick_version)"
if [ -z "$new_ver" ] || [ "$new_ver" = "custom" ]; then
  read -r -p "Enter custom version: " new_ver
fi
[[ "$new_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid semver format: $new_ver"

new_tag="${TAG_PREFIX}${new_ver}"
msg="${TAG_MSG_PREFIX}${new_ver}"

# --- Final Confirmation ---
echo
echo "Plan:"
echo "  Action:         Bump $file_ver -> $new_ver"
echo "  Tag:            $new_tag"
echo "  Commit Msg:     $msg"
[ "$DRY_RUN" = true ] && echo "  MODE:           *** DRY RUN ***"
echo

read -r -p "Proceed? [y/N] " ans
case "${ans:-N}" in [yY]*) ;; *) die "Aborted" ;; esac

# --- Execution ---

# 1. Update file
info "Updating $FILE..."
if [ "$DRY_RUN" = false ]; then
  sed -i.tmp -E "0,/(\.version[[:space:]]*=[[:space:]]*)\"[^\"]*\"/ s//\1\"$new_ver\"/" "$FILE"
  rm -f "${FILE}.tmp"
  zig fmt "$FILE"
else
  echo "[DRY-RUN] Update .version in $FILE and run zig fmt"
fi

# 2. Pre-push tag check
if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$new_tag" >/dev/null 2>&1; then
  die "Remote $REMOTE already has tag $new_tag. Collision detected."
fi

# 3. Git Operations
info "Committing and Pushing..."
run git add "$FILE"
run git commit -m "$msg"
run git push "$REMOTE" "$BRANCH"

info "Tagging..."
run git tag -a "$new_tag" -m "$msg"
run git push "$REMOTE" "$new_tag"

info "Successfully released $new_tag"
