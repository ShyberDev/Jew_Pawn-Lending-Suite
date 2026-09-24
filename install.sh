#!/usr/bin/env bash
# =============================================================================
#  Jew_Pawn-Lending-Suite  —  one-command installer
# -----------------------------------------------------------------------------
#  Downloads Frappe + ERPNext at pinned commits, installs the vendored
#  jewellery_management / lending / pawn_shop apps, creates a site and
#  installs everything. You never install Frappe separately.
#
#  Usage:
#     ./install.sh                         # interactive defaults
#     ./install.sh --site myshop.local --admin-password 'Secret123'
#     DB_ROOT_PASSWORD='root' ./install.sh --non-interactive
#
#  Options:
#     --site NAME              site name                (default: library.local)
#     --bench-dir PATH         bench folder             (default: ~/frappe-bench)
#     --admin-password PASS    site Administrator pass  (default: admin)
#     --db-root-password PASS  MariaDB root password
#     --non-interactive        never prompt (needs env/flags for passwords)
#     --skip-system-deps       do not apt-install system packages
#     --help
# =============================================================================
set -euo pipefail

# --------------------------------------------------------------------------- #
# 0.  locate bundle + load pinned versions
# --------------------------------------------------------------------------- #
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "$BUNDLE_DIR/versions.env"

SITE_NAME="${SITE_NAME:-library.local}"
BENCH_DIR="${BENCH_DIR:-$HOME/frappe-bench}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
NON_INTERACTIVE=0
SKIP_SYSTEM_DEPS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --site)               SITE_NAME="$2"; shift 2 ;;
    --bench-dir)          BENCH_DIR="$2"; shift 2 ;;
    --admin-password)     ADMIN_PASSWORD="$2"; shift 2 ;;
    --db-root-password)   DB_ROOT_PASSWORD="$2"; shift 2 ;;
    --non-interactive)    NON_INTERACTIVE=1; shift ;;
    --skip-system-deps)   SKIP_SYSTEM_DEPS=1; shift ;;
    --help|-h)            sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# 1.  pre-flight checks
# --------------------------------------------------------------------------- #
[ "$(id -u)" -eq 0 ] && die "Do not run this as root. Run as your normal user (sudo will be requested when needed)."
[ -d "$BUNDLE_DIR/apps/pawn_shop" ] || die "Run this from inside the bundle folder (apps/ not found)."

log "Bundle    : $BUNDLE_DIR"
log "Bench dir : $BENCH_DIR"
log "Site      : $SITE_NAME"
log "Pinned    : frappe ${FRAPPE_COMMIT:0:9} / erpnext ${ERPNEXT_COMMIT:0:9}"

if [ "$NON_INTERACTIVE" -eq 0 ]; then
  read -r -p "Continue with these settings? [Y/n] " _ans
  case "${_ans:-Y}" in [Yy]*) ;; *) die "Aborted." ;; esac
fi

SUDO=""
if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

# --------------------------------------------------------------------------- #
# 2.  system packages (Debian / Ubuntu / Kali / Mint)
# --------------------------------------------------------------------------- #
if [ "$SKIP_SYSTEM_DEPS" -eq 0 ]; then
  log "Installing system packages (git, python, node, yarn, mariadb, redis, ...)"
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -y
    $SUDO apt-get install -y \
      git curl wget build-essential pkg-config \
      python3 python3-dev python3-venv python3-pip \
      mariadb-server mariadb-client libmariadb-dev \
      redis-server \
      nodejs npm \
      cron xvfb libfontconfig1 libxrender1 libxext6 libx11-6 \
      wkhtmltopdf || warn "Some packages failed to install; continuing."
    if ! command -v yarn >/dev/null 2>&1; then
      $SUDO npm install -g yarn || warn "yarn install failed; continuing."
    fi
  else
    warn "Non-apt system. Please install manually: git python3-venv mariadb-server redis-server nodejs yarn wkhtmltopdf"
  fi
else
  log "Skipping system packages (--skip-system-deps)."
fi

# --------------------------------------------------------------------------- #
# 3.  bench CLI
# --------------------------------------------------------------------------- #
if ! command -v bench >/dev/null 2>&1; then
  log "Installing the 'bench' CLI"
  if command -v pipx >/dev/null 2>&1; then
    pipx install frappe-bench
  else
    python3 -m pip install --user --break-system-packages frappe-bench 2>/dev/null \
      || python3 -m pip install --user frappe-bench
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi
command -v bench >/dev/null 2>&1 || die "bench is still not on PATH. Add ~/.local/bin to PATH and re-run."
log "bench $(bench --version)"

# --------------------------------------------------------------------------- #
# 4.  MariaDB + Redis
# --------------------------------------------------------------------------- #
log "Starting MariaDB and Redis"
$SUDO systemctl enable --now mariadb 2>/dev/null || $SUDO service mariadb start 2>/dev/null || true
$SUDO systemctl enable --now redis-server 2>/dev/null || $SUDO service redis-server start 2>/dev/null || true

if [ -z "$DB_ROOT_PASSWORD" ] && [ "$NON_INTERACTIVE" -eq 0 ]; then
  read -r -s -p "MariaDB root password (leave blank if none): " DB_ROOT_PASSWORD; echo
fi

# --------------------------------------------------------------------------- #
# 5.  bench init (Frappe) — pinned
# --------------------------------------------------------------------------- #
if [ -d "$BENCH_DIR/apps/frappe" ]; then
  log "Bench already exists at $BENCH_DIR — reusing it."
else
  log "Creating bench + cloning Frappe ($FRAPPE_BRANCH)"
  bench init --frappe-branch "$FRAPPE_BRANCH" --python python3 "$BENCH_DIR"
fi
cd "$BENCH_DIR"

if [ -d apps/frappe/.git ]; then
  log "Pinning Frappe to ${FRAPPE_COMMIT:0:9}"
  git -C apps/frappe fetch --all --quiet || true
  git -C apps/frappe checkout --quiet "$FRAPPE_COMMIT" \
    || warn "Could not checkout Frappe $FRAPPE_COMMIT (upstream may have moved). Staying on $FRAPPE_BRANCH."
fi

# --------------------------------------------------------------------------- #
# 6.  ERPNext — pinned
# --------------------------------------------------------------------------- #
if [ -d apps/erpnext ]; then
  log "ERPNext already present."
else
  log "Fetching ERPNext ($ERPNEXT_BRANCH)"
  bench get-app erpnext --branch "$ERPNEXT_BRANCH"
fi
if [ -d apps/erpnext/.git ]; then
  log "Pinning ERPNext to ${ERPNEXT_COMMIT:0:9}"
  git -C apps/erpnext fetch --all --quiet || true
  git -C apps/erpnext checkout --quiet "$ERPNEXT_COMMIT" \
    || warn "Could not checkout ERPNext $ERPNEXT_COMMIT. Staying on $ERPNEXT_BRANCH."
fi

# --------------------------------------------------------------------------- #
# 7.  vendored custom apps
# --------------------------------------------------------------------------- #
log "Installing vendored apps: $VENDORED_APPS"
for app in $VENDORED_APPS; do
  [ -d "$BUNDLE_DIR/apps/$app" ] || die "Missing vendored app: $app"
  rm -rf "apps/$app"
  cp -a "$BUNDLE_DIR/apps/$app" "apps/$app"
  grep -qxF "$app" sites/apps.txt 2>/dev/null || echo "$app" >> sites/apps.txt
  log "  + $app"
done

log "Installing Python requirements for all apps"
bench setup requirements --python || warn "setup requirements reported errors; continuing."

# --------------------------------------------------------------------------- #
# 8.  create site
# --------------------------------------------------------------------------- #
if [ -d "sites/$SITE_NAME" ]; then
  log "Site $SITE_NAME already exists — reusing."
else
  log "Creating site $SITE_NAME"
  NEW_SITE_ARGS=(--admin-password "$ADMIN_PASSWORD")
  [ -n "$DB_ROOT_PASSWORD" ] && NEW_SITE_ARGS+=(--mariadb-root-password "$DB_ROOT_PASSWORD")
  bench new-site "$SITE_NAME" "${NEW_SITE_ARGS[@]}" --no-mariadb-socket
fi
bench use "$SITE_NAME" >/dev/null
bench --site "$SITE_NAME" set-config developer_mode 1 >/dev/null 2>&1 || true

# --------------------------------------------------------------------------- #
# 9.  install apps (order matters: erpnext first)
# --------------------------------------------------------------------------- #
log "Installing apps on the site"
for app in erpnext jewellery_management lending pawn_shop; do
  if bench --site "$SITE_NAME" list-apps 2>/dev/null | grep -qxF "$app"; then
    log "  = $app (already installed)"
  else
    log "  + $app"
    bench --site "$SITE_NAME" install-app "$app"
  fi
done

# --------------------------------------------------------------------------- #
# 10. build assets
# --------------------------------------------------------------------------- #
log "Building front-end assets (this can take a few minutes)"
bench build || warn "bench build reported errors; run it again if the UI looks unstyled."

# --------------------------------------------------------------------------- #
# 11. done
# --------------------------------------------------------------------------- #
cat <<EOF

=============================================================================
  ✅  Installation complete
=============================================================================

  Start the servers:
      cd $BENCH_DIR
      bench start

  Then open:
      http://$SITE_NAME:8000/desk

  Login:  Administrator / $ADMIN_PASSWORD

  Daily commands:
      sudo systemctl start mariadb
      cd $BENCH_DIR
      bench start
      # open http://$SITE_NAME:8000/desk

  If the desk looks grey / sidebar is empty, see README_FIRST.md
  ("Fixing the grey desk / sidebar").

=============================================================================
EOF
