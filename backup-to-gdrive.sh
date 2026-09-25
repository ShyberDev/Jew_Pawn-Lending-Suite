#!/usr/bin/env bash
#
# backup-to-gdrive.sh — Frappe full backup + off-site copy to Google Drive.
#
# This is the DISASTER-RECOVERY half of the suite (the mobile app handles
# live two-way sync). It produces a complete, restorable snapshot of the site
# (database + public files + private files) and copies it off the laptop, so a
# lost/stolen/broken laptop is fully recoverable.
#
# ---------------------------------------------------------------------------
# ONE-TIME SETUP (see docs/BACKUP_AND_RECOVERY.md for the full walkthrough)
#
#   1. Install rclone:            curl https://rclone.org/install.sh | sudo bash
#   2. Configure a Google Drive:  rclone config        (name it: gdrive)
#   3. (Optional, recommended)    rclone config        (create a "crypt" remote
#                                  wrapping gdrive:JewelleryBackups)
#   4. Schedule it (crontab -e), e.g. every night at 2:15am:
#        15 2 * * *  /home/shyam/Jew_Pawn-Lending-Suite/backup-to-gdrive.sh \
#                      >> /home/shyam/backup.log 2>&1
# ---------------------------------------------------------------------------
#
# Usage:
#   ./backup-to-gdrive.sh                 # backup + upload + prune
#   ./backup-to-gdrive.sh --no-upload     # local backup only
#   ./backup-to-gdrive.sh --export-only   # Excel exports only (no DB backup)
#   ./backup-to-gdrive.sh --config FILE   # use a specific config file
#   ./backup-to-gdrive.sh --list          # list backups on the remote
#   ./backup-to-gdrive.sh --restore NAME  # restore (interactive, DANGEROUS)
#
# In addition to the Frappe snapshot it also writes Excel exports
# (full / khata / pawn / customers) via tools/export_excel.py and uses a
# change-fingerprint so a run with NO data changes is skipped entirely —
# Google Drive never fills with duplicate backups.
#
set -euo pipefail

# ------------------------------- config ------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SITE="${SITE:-library.local}"
BENCH_DIR="${BENCH_DIR:-$HOME/frappe-bench}"
# Google Drive destination. If you set up an rclone "crypt" remote, point this
# at it (e.g. "gdrive-crypt:JewelleryBackups") for end-to-end encryption.
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive:JewelleryBackups}"
# Keep this many days of backups locally and on the remote.
RETENTION_DAYS="${RETENTION_DAYS:-30}"
# Skip the upload if the local disk is below this % free (safety).
MIN_FREE_PCT="${MIN_FREE_PCT:-5}"
# Bench python environment + Excel export tool.
ENV_PY="${ENV_PY:-$BENCH_DIR/env/bin/python}"
EXPORT_SCRIPT="${EXPORT_SCRIPT:-$SCRIPT_DIR/tools/export_excel.py}"

# Allow overrides from an optional config file next to this script.
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/backup.env}"
if [[ -f "$CONFIG_FILE" ]]; then
	# shellcheck disable=SC1090
	source "$CONFIG_FILE"
fi

BACKUP_DIR="$BENCH_DIR/sites/$SITE/backups"
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
# Where the change-detection fingerprint is stored (enables "skip if unchanged").
FINGERPRINT_FILE="$BACKUP_DIR/.last-fingerprint"

log()  { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die()  { log "ERROR: $*" >&2; exit 1; }

# ------------------------------- helpers -----------------------------------
require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "'$1' not found. $2"
}

# ---------------------------------------------------------------------------
# Change detection (dedup) + Excel exports
# ---------------------------------------------------------------------------

data_fingerprint() {
	(cd "$BENCH_DIR" && "$ENV_PY" "$EXPORT_SCRIPT" fingerprint --site "$SITE" 2>/dev/null)
}

# Returns 0 (skip) when the data is byte-for-byte identical to the last backup.
skip_if_unchanged() {
	[[ -f "$FINGERPRINT_FILE" ]] || return 1
	local prev now
	prev="$(cat "$FINGERPRINT_FILE")"
	now="$(data_fingerprint)"
	[[ -n "$now" && -n "$prev" && "$now" == "$prev" ]]
}

store_fingerprint() {
	data_fingerprint > "$FINGERPRINT_FILE"
	log "stored change-fingerprint $(cat "$FINGERPRINT_FILE" | cut -c1-16)…"
}

do_excel_export() {
	log "writing Excel exports (full / khata / pawn / customers) ..."
	(cd "$BENCH_DIR" && "$ENV_PY" "$EXPORT_SCRIPT" export --site "$SITE" --out "$BACKUP_DIR" --stamp "$STAMP")
}

check_disk() {
	local pct
	pct="$(df -P "$BENCH_DIR" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
	if (( pct > (100 - MIN_FREE_PCT) )); then
		die "disk ${pct}% used; refusing to back up (MIN_FREE_PCT=$MIN_FREE_PCT)"
	fi
}

# ------------------------------- actions -----------------------------------
do_backup() {
	log "backing up site '$SITE' in '$BENCH_DIR' ..."
	check_disk
	cd "$BENCH_DIR"
	# --with-files = database + public files + private files, in one command.
	bench --site "$SITE" backup --with-files
	log "backup complete; files in $BACKUP_DIR"
}

latest_backup_files() {
	# Emit the newest database backup (without extension) so we can pair it
	# with its sibling files archives.
	find "$BACKUP_DIR" -maxdepth 1 -name '*_database.sql.gz' -printf '%f\n' \
		| sort | tail -1 | sed 's/_database\.sql\.gz$//'
}

do_upload() {
	require_cmd rclone "Install it: curl https://rclone.org/install.sh | sudo bash"
	[[ -d "$BACKUP_DIR" ]] || die "no backup dir at $BACKUP_DIR"
	log "uploading $BACKUP_DIR -> $RCLONE_REMOTE ..."
	rclone copy "$BACKUP_DIR" "$RCLONE_REMOTE" \
		--include "*_database.sql.gz" \
		--include "*_files.tar" \
		--include "*_private_files.tar" \
		--include "*.xlsx" \
		--include "*.json" \
		--transfers 2 --retries 5 --low-level-retries 10 \
		--stats-one-line --stats 30s
	log "upload complete"
}

do_prune() {
	log "pruning local backups older than ${RETENTION_DAYS} days ..."
	find "$BACKUP_DIR" -maxdepth 1 -type f \
		\( -name '*.sql.gz' -o -name '*_files.tar' -o -name '*_private_files.tar' -o -name '*.xlsx' -o -name '*.json' \) \
		-mtime +"$RETENTION_DAYS" -print -delete || true
	require_cmd rclone "Install it: curl https://rclone.org/install.sh | sudo bash"
	log "pruning remote backups older than ${RETENTION_DAYS} days ..."
	rclone delete "$RCLONE_REMOTE" --min-age "${RETENTION_DAYS}d" || true
	rclone rmdirs "$RCLONE_REMOTE" --leave-root || true
	log "prune complete"
}

do_list() {
	require_cmd rclone "Install it: curl https://rclone.org/install.sh | sudo bash"
	rclone ls "$RCLONE_REMOTE"
}

do_restore() {
	local base="$1"
	[[ -n "$base" ]] || die "usage: $0 --restore <backup-base-name>"
	cat <<EOF

!! DANGER !!
This will OVERWRITE the database and files of site '$SITE' with backup:
    $base

Make sure you have a backup of the CURRENT state first. Type exactly
"RESTORE $SITE" to continue:
EOF
	read -r confirm
	[[ "$confirm" == "RESTORE $SITE" ]] || die "aborted"
	cd "$BENCH_DIR"
	local db="$BACKUP_DIR/${base}_database.sql.gz"
	local pub="$BACKUP_DIR/${base}_files.tar"
	local priv="$BACKUP_DIR/${base}_private_files.tar"
	[[ -f "$db" ]] || die "missing $db"
	bench --site "$SITE" restore "$db" \
		${pub:+--with-public-files "$pub"} \
		${priv:+--with-private-files "$priv"}
	log "restore complete; run: bench --site $SITE migrate"
}

# ------------------------------- main --------------------------------------
MODE="full"
case "${1:-}" in
	--no-upload)   MODE="local" ;;
	--list)        MODE="list" ;;
	--export-only) MODE="export" ;;
	--restore)     MODE="restore"; shift ;;
	--config)      CONFIG_FILE="$2"; source "$CONFIG_FILE" ;;
	-h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	"")            ;;
	*)             die "unknown option: $1 (try --help)" ;;
esac

case "$MODE" in
	list)   do_list ;;
	restore) do_restore "${1:-}" ;;

	# Excel refresh / sharing — no database backup, no upload. Use this when
	# you simply want an up-to-date shareable Excel set.
	export) do_excel_export ;;

	# A full run. First check whether ANYTHING changed since the last backup:
	# if not, we skip the whole job so Google Drive never fills with duplicate
	# snapshots. If changed: bench backup -> Excel exports -> upload -> prune.
	local|full)
		if skip_if_unchanged; then
			log "no data changes since last backup — skipping (no duplicates)"
			exit 0
		fi
		do_backup
		do_excel_export
		store_fingerprint
		if [[ "$MODE" == "local" ]]; then
			log "skipping upload (--no-upload)"
		else
			do_upload
			do_prune
		fi
		;;
esac

log "done."
