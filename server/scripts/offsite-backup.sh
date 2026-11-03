#!/bin/bash
# Sends an encrypted copy of the nightly backup off the server (README.md step 31).
#
# Like a safe-deposit box at the bank: the nightly backup (step 30) is the copy in your desk
# drawer, this one survives the house burning down. It's locked with a password before it
# leaves the server, so Google only ever sees scrambled data in your Drive.
#
# It uses restic, which only uploads what changed since last night, so after the first upload
# each night sends a few megabytes, not the whole backup.
#
#   sudo offsite-backup.sh            back up now (backup-config.sh runs this every night)
#   sudo offsite-backup.sh connect-drive   link Google Drive, once (asks for rclone authorize's output)
#   sudo offsite-backup.sh init       make the encrypted store, once
#   sudo offsite-backup.sh list       show the saved copies
#   sudo offsite-backup.sh check      prove a slice of the stored data can be read back
#   sudo offsite-backup.sh restore    download the newest copy to /data/backups/offsite-restore

set -euo pipefail

SERVER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SERVER_DIR/.env"
env_value() { grep "^$1=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d "'\"" || true; }

BACKUP_DIR="$(env_value BACKUP_DIR)"; BACKUP_DIR="${BACKUP_DIR:-/data/backups/config}"
PUSH_URL="$(env_value OFFSITE_PUSH_URL)"
export RESTIC_REPOSITORY="$(env_value OFFSITE_REPOSITORY)"
export RESTIC_PASSWORD="$(env_value OFFSITE_PASSWORD)"
export RESTIC_CACHE_DIR=/var/cache/restic

say() { echo "$(date '+%F %T') offsite: $*"; }
fail() { say "FAILED: $*"; exit 1; }
trap 'say "FAILED on line $LINENO of $0"' ERR

[ "$(id -u)" = 0 ] || fail "run it with sudo"

if [ "${1:-}" = connect-drive ]; then
  command -v rclone >/dev/null || fail "rclone isn't installed: sudo apt install -y rclone"
  read -rp "Paste what rclone authorize printed between the arrows: " t
  # Newer rclone prints it base64-wrapped ("eyJ..."), older prints the raw {"access_token":...}.
  tok=$(python3 -c '
import sys, json, base64
s = sys.argv[1].strip()
if s.startswith("{"):
    d = json.loads(s)
else:
    s = s.replace("+", "-").replace("/", "_")
    d = json.loads(base64.urlsafe_b64decode(s + "=" * (-len(s) % 4)))
print(d["token"] if "token" in d else json.dumps(d))' "$t") || fail "that doesn't look like rclone's output, copy it again"
  rclone config create gdrive drive scope=drive.file use_trash=false token="$tok" --non-interactive >/dev/null
  rclone lsd gdrive: >/dev/null || fail "Google didn't accept it: run rclone authorize on the laptop again"
  say "Google Drive connected"
  exit 0
fi

command -v restic >/dev/null || fail "restic isn't installed: sudo apt install -y restic"
[ -n "$RESTIC_REPOSITORY" ] || fail "OFFSITE_REPOSITORY is blank in $ENV_FILE (README.md step 31)"
[ -n "$RESTIC_PASSWORD" ] || fail "OFFSITE_PASSWORD is blank in $ENV_FILE (README.md step 31)"
case "$RESTIC_REPOSITORY" in rclone:*)   # Google Drive goes through rclone (README.md step 31c).
  command -v rclone >/dev/null || fail "rclone isn't installed: sudo apt install -y rclone"
esac

case "${1:-backup}" in
  init)
    restic init
    say "Encrypted store ready. Keep OFFSITE_PASSWORD somewhere off the server: without it the copy can't be opened."
    ;;

  list)
    restic snapshots
    ;;

  check)
    restic check --read-data-subset=5%
    ;;

  restore)
    target=/data/backups/offsite-restore
    restic restore latest --target "$target"
    chmod 700 "$target"
    say "Downloaded to $target (config/ is every app's folder, extras/server.env is your .env)"
    ;;

  backup)
    [ -d "$BACKUP_DIR/.staging/config" ] || fail "no local backup in $BACKUP_DIR yet: run backup-config.sh first"
    say "Uploading what changed since last time"
    # The .staging folder is last night's backup unpacked. Backing that up (not the .tar.gz)
    # is what lets restic skip everything that hasn't changed.
    cd "$BACKUP_DIR/.staging"
    restic unlock   # Clears a lock left behind if a past run was cut off (only stale ones).
    restic backup --host jevans-server --tag nightly config extras

    # Keep 14 nightly copies, then one a week for 8 weeks, then one a month for a year.
    restic forget --host jevans-server --tag nightly --keep-daily 14 --keep-weekly 8 --keep-monthly 12
    # Actually freeing the space takes more work, so only on Sundays.
    if [ "$(date +%u)" = 7 ]; then
      say "Sunday tidy-up: removing data no copy needs any more"
      restic prune
    fi

    say "Done: $(restic snapshots --host jevans-server --tag nightly --compact 2>/dev/null | grep -c '^[0-9a-f]\{8\} ') copies stored off the server"
    if [ -n "$PUSH_URL" ]; then
      curl -fsS -m 10 --retry 3 --retry-delay 20 --retry-all-errors -o /dev/null "$PUSH_URL" || \
        say "WARNING: couldn't reach Uptime Kuma"
    fi
    ;;

  *)
    echo "Use: $0 [init | list | check | restore]"
    exit 1
    ;;
esac
