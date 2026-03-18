#!/usr/bin/env bash
# dev-cleanup.sh — Move re-fetchable dev artifacts out of a project tree.
#
# Usage:
#   ./dev-cleanup.sh <source_dir> [output_dir] [--dry-run]
#
# Examples:
#   ./dev-cleanup.sh ~/projects --dry-run              # preview what would move
#   ./dev-cleanup.sh ~/projects                        # moves to ./cleanup-output
#   ./dev-cleanup.sh ~/projects ~/backup/dev-artifacts # custom output dir

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
SOURCE=""
OUTPUT=""
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      sed -n '2,9s/^# //p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$SOURCE" ]]; then
        SOURCE="$arg"
      elif [[ -z "$OUTPUT" ]]; then
        OUTPUT="$arg"
      fi
      ;;
  esac
done

if [[ -z "$SOURCE" ]]; then
  echo "Usage: $0 <source_dir> [output_dir] [--dry-run]"
  exit 1
fi

if [[ ! -d "$SOURCE" ]]; then
  echo "Error: source directory '$SOURCE' does not exist"
  exit 1
fi

SOURCE="$(cd "$SOURCE" && pwd)"
OUTPUT="${OUTPUT:-./cleanup-output}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"

if [[ "$OUTPUT" == "$SOURCE" ]]; then
  echo "Error: output directory cannot be the same as source directory"
  exit 1
fi

# ── Counters ─────────────────────────────────────────────────────────────────
MOVED_COUNT=0
TOTAL_KB=0

human_size() {
  local kb=$1
  if (( kb >= 1048576 )); then
    awk "BEGIN {printf \"%.1f GB\", $kb / 1048576}"
  elif (( kb >= 1024 )); then
    awk "BEGIN {printf \"%.1f MB\", $kb / 1024}"
  else
    printf "%d KB" "$kb"
  fi
}

move_item() {
  local item="$1"
  [[ -e "$item" ]] || return 0

  local rel="${item#"$SOURCE"/}"
  local dest="$OUTPUT/$rel"
  local dest_parent
  dest_parent="$(dirname "$dest")"

  if $DRY_RUN; then
    local size
    size=$(du -sk "$item" 2>/dev/null | cut -f1) || size=0
    printf "  [DRY RUN] %-10s %s\n" "$(human_size "$size")" "$rel"
    TOTAL_KB=$((TOTAL_KB + size))
  else
    mkdir -p "$dest_parent"
    mv "$item" "$dest"
    printf "  moved     %s\n" "$rel"
  fi

  MOVED_COUNT=$((MOVED_COUNT + 1))
}

# ── Banner ───────────────────────────────────────────────────────────────────
echo "──────────────────────────────────────────"
echo "  dev-cleanup"
echo "──────────────────────────────────────────"
echo "  Source : $SOURCE"
echo "  Output : $OUTPUT"
echo "  Mode   : $($DRY_RUN && echo 'DRY RUN (nothing will be moved)' || echo 'LIVE')"
echo "──────────────────────────────────────────"
echo ""

# ── Directories to clean (re-fetchable / regeneratable) ─────────────────────
CLEAN_DIRS=(
  # Version control
  .git
  .svn
  .hg

  # ── JavaScript / Node ──
  node_modules
  bower_components
  .npm
  .pnpm-store
  .next            # Next.js build cache
  .nuxt            # Nuxt 2 build
  .output          # Nuxt 3 build
  .turbo           # Turborepo cache
  .parcel-cache    # Parcel bundler
  .angular         # Angular cache
  .svelte-kit      # SvelteKit

  # ── Python ──
  __pycache__
  .venv
  venv
  .virtualenv
  .mypy_cache
  .pytest_cache
  .ruff_cache
  .tox
  .eggs
  htmlcov          # coverage HTML reports

  # ── iOS / macOS / Xcode ──
  DerivedData
  Pods             # CocoaPods (re-fetch with pod install)
  xcuserdata       # Xcode per-user data

  # ── Flutter / Dart ──
  .dart_tool
  .fvm

  # ── Rust ──
  target

  # ── Java / Kotlin / Android ──
  .gradle

  # ── PHP ──
  vendor           # Composer (re-fetch with composer install)

  # ── Ruby ──
  .bundle

  # ── Build outputs (common across ecosystems) ──
  dist
  build
  out
  .build           # Swift Package Manager

  # ── Caches ──
  .cache
  .sass-cache
  .eslintcache
  .stylelintcache

  # ── Test / coverage ──
  coverage
  .coverage
  .nyc_output

  # ── Infrastructure ──
  .terraform
  .terragrunt-cache

  # ── Temp ──
  tmp
  .tmp
)

echo "=== Directories ==="
for dirname in "${CLEAN_DIRS[@]}"; do
  while IFS= read -r -d '' match; do
    # Skip anything inside the output directory
    [[ "$match" == "$OUTPUT"* ]] && continue
    move_item "$match"
  done < <(find "$SOURCE" -name "$dirname" -type d -prune -print0 2>/dev/null || true)
done

# ── Egg-info directories (glob pattern) ─────────────────────────────────────
while IFS= read -r -d '' match; do
  [[ "$match" == "$OUTPUT"* ]] && continue
  move_item "$match"
done < <(find "$SOURCE" -name "*.egg-info" -type d -prune -print0 2>/dev/null || true)

# ── Individual files to clean ────────────────────────────────────────────────
CLEAN_FILES=(
  "*.pyc"
  "*.pyo"
  ".DS_Store"
  "Thumbs.db"
)

echo ""
echo "=== Files ==="
for pattern in "${CLEAN_FILES[@]}"; do
  while IFS= read -r -d '' match; do
    [[ "$match" == "$OUTPUT"* ]] && continue
    move_item "$match"
  done < <(find "$SOURCE" -name "$pattern" -not -type d -print0 2>/dev/null || true)
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
if $DRY_RUN; then
  echo "  DRY RUN complete"
  echo "  Items found  : $MOVED_COUNT"
  echo "  Space to free: $(human_size $TOTAL_KB)"
else
  echo "  Cleanup complete"
  echo "  Items moved  : $MOVED_COUNT"
fi
echo "──────────────────────────────────────────"

if $DRY_RUN && (( MOVED_COUNT > 0 )); then
  echo ""
  echo "  Run without --dry-run to execute."
fi
