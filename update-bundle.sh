#!/usr/bin/env bash
# =============================================================================
#  update-bundle.sh  —  sync the LIVE bench apps into this bundle repo
# -----------------------------------------------------------------------------
#  After you change the apps in your working bench (~/frappe-bench/apps/*),
#  run this to copy those changes into the bundle's apps/ folder, so the
#  one-repo download always matches what you are actually running.
#
#  Usage:
#     ./update-bundle.sh                 # sync + show git status
#     ./update-bundle.sh --commit        # sync + git commit
#     ./update-bundle.sh --commit --push # sync + commit + push
#     ./update-bundle.sh --dry-run       # show what would change, change nothing
#     ./update-bundle.sh --bench-apps /path/to/frappe-bench/apps
#
#  Options:
#     --bench-apps PATH   bench apps dir (default: ~/frappe-bench/apps)
#     --commit            git add + commit in the bundle
#     --push              git push after commit (implies --commit)
#     --dry-run           preview only
#     --help
# =============================================================================
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_APPS="${BENCH_APPS:-$HOME/frappe-bench/apps}"
APPS="jewellery_management lending pawn_shop"
DRY_RUN=0
DO_COMMIT=0
DO_PUSH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bench-apps) BENCH_APPS="$2"; shift 2 ;;
    --commit)     DO_COMMIT=1; shift ;;
    --push)       DO_PUSH=1; DO_COMMIT=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --help|-h)    sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$BUNDLE_DIR/apps" ] || die "Run this from inside the bundle folder."
[ -d "$BENCH_APPS" ] || die "Bench apps dir not found: $BENCH_APPS"
[ -d "$BUNDLE_DIR/.git" ] || die "Bundle is not a git repo: $BUNDLE_DIR"

RSYNC_OPTS=(-a --delete
  --exclude='.git' --exclude='__pycache__' --exclude='*.pyc'
  --exclude='node_modules' --exclude='.pytest_cache' --exclude='.venv')
[ "$DRY_RUN" -eq 1 ] && RSYNC_OPTS+=(--dry-run --itemize-changes)

log "Bundle   : $BUNDLE_DIR"
log "Bench    : $BENCH_APPS"
log "Apps     : $APPS"
[ "$DRY_RUN" -eq 1 ] && warn "DRY RUN — nothing will be written."

for app in $APPS; do
  src="$BENCH_APPS/$app/"
  dst="$BUNDLE_DIR/apps/$app/"
  [ -d "$src" ] || { warn "Skipping $app (not in bench)"; continue; }
  [ -d "$dst" ] || { warn "Skipping $app (not in bundle)"; continue; }
  log "Syncing $app"
  rsync "${RSYNC_OPTS[@]}" "$src" "$dst"
done

cd "$BUNDLE_DIR"
if [ "$DRY_RUN" -eq 1 ]; then
  log "Dry run complete. Re-run without --dry-run to apply."
  exit 0
fi

log "Bundle git status:"
git status --short

if [ "$DO_COMMIT" -eq 1 ]; then
  if git diff --quiet && git diff --cached --quiet; then
    log "No changes to commit."
  else
    git add -A
    git -c user.name="$(git config user.name || echo 'ShyberDev')" \
        -c user.email="$(git config user.email || echo 'shyamsailolugu@gmail.com')" \
        commit -q -m "chore: sync apps from bench $(date +%Y-%m-%d\ %H:%M)"
    log "Committed: $(git log --oneline -1)"
  fi
fi

if [ "$DO_PUSH" -eq 1 ]; then
  log "Pushing to origin..."
  git push origin "$(git rev-parse --abbrev-ref HEAD)"
  log "Pushed."
fi

log "Done. To refresh your running bench from the bundle instead, copy apps back"
log "and run:  bench setup requirements && bench build && bench restart"
