#!/bin/bash
# Nightly backup of every app's settings (README.md step 29).
#
# Like photographing a busy kitchen: first a slow, careful photo while everyone keeps working
# (blurry in places), then everyone freezes for a few seconds while a quick second photo fixes
# only the blurry bits. The freeze is short because almost everything was already captured.
#
#   1. Copy /opt/media/config to the media drive while the apps run (slow, the first night only).
#   2. Stop the apps that keep databases, copy again (only what changed: seconds), start them.
#   3. Pack that copy into one dated .tar.gz, keep the newest $BACKUP_KEEP_DAYS, delete older ones.
#   4. Tell Uptime Kuma "backup done", so a missed night buzzes your phone.
#
# Run it as root (sudo), from root's crontab. It reads its settings from server/.env.

set -euo pipefail

SERVER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SERVER_DIR/.env"

env_value() {   # The value of one .env line, without quotes. Blank if missing.
  grep "^$1=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d "'\"" || true
}

CONFIG_DIR="$(env_value CONFIG_DIR)"
BACKUP_DIR="$(env_value BACKUP_DIR)";             BACKUP_DIR="${BACKUP_DIR:-/data/backups/config}"
KEEP_DAYS="$(env_value BACKUP_KEEP_DAYS)";        KEEP_DAYS="${KEEP_DAYS:-14}"
PUSH_URL="$(env_value BACKUP_PUSH_URL)"
STAGING="$BACKUP_DIR/.staging"

# Apps with nothing worth freezing for: no database, or (AdGuard) one the house needs to stay up.
# Everything else that is running gets stopped for the few seconds of step 2.
KEEP_RUNNING="gluetun flaresolverr jellyfin-discovery caddy adguard homepage dockerproxy beszel-agent"

# Compare file times to the nanosecond, so a database written twice in one second is still re-copied.
RSYNC=(rsync -a --delete --numeric-ids --modify-window=-1)

# Things that are big and come back by themselves (posters, caches, logs, the apps' own zips).
EXCLUDES=(
  --exclude=/jellyfin/cache/ --exclude=/jellyfin/data/transcodes/ --exclude=/jellyfin/data/metadata/
  --exclude=/adguard/work/data/querylog.json* --exclude=/beszel/socket/
  --exclude=MediaCover/ --exclude=logs/ --exclude=log/ --exclude=Logs/ --exclude=/sonarr/Backups/
  --exclude=/radarr/Backups/ --exclude=/prowlarr/Backups/ --exclude=/bazarr/backup/ --exclude='*.pid'
  --exclude='/*.before-restore-*/'
)

say() { echo "$(date '+%F %T') $*"; }
fail() { say "FAILED: $*"; exit 1; }
trap 'say "FAILED on line $LINENO of $0"' ERR

[ "$(id -u)" = 0 ] || fail "run it with sudo"
command -v rsync >/dev/null || fail "rsync isn't installed: sudo apt install -y rsync"
[ -n "$CONFIG_DIR" ] && [ -d "$CONFIG_DIR" ] || fail "CONFIG_DIR in $ENV_FILE is missing or not a folder"

# If the backups go on /data, the media drive must really be there. Otherwise they'd quietly
# land on the small system drive underneath and fill it up.
case "$BACKUP_DIR" in /data/*)
  mountpoint -q /data && [ -b "$(findmnt -no SOURCE /data)" ] || fail "the media drive isn't mounted at /data"
esac

mkdir -p "$STAGING/config" "$STAGING/extras"
chmod 700 "$BACKUP_DIR"   # The backups hold passwords and keys: root only.

free_kb=$(df -Pk "$BACKUP_DIR" | awk 'NR==2 {print $4}')
[ "$free_kb" -gt 5000000 ] || fail "less than 5 GB free on $BACKUP_DIR"

say "Pass 1: copying $CONFIG_DIR while the apps run"
"${RSYNC[@]}" "${EXCLUDES[@]}" "$CONFIG_DIR/" "$STAGING/config/" || \
  [ $? = 24 ]   # 24 = "a file vanished while copying", normal while apps run; pass 2 fixes it.

cd "$SERVER_DIR"
running=$(docker compose ps --services --status running)
to_stop=""
for s in $running; do
  case " $KEEP_RUNNING uptime-kuma " in *" $s "*) ;; *) to_stop="$to_stop $s" ;; esac
done
kuma_running=no
case " $(echo $running) " in *" uptime-kuma "*) kuma_running=yes ;; esac

restart_apps() {   # Runs however the script ends, so a failed copy never leaves the apps off.
  trap - EXIT
  if [ -n "$to_stop" ]; then
    say "Starting:$to_stop"
    docker compose start $to_stop || say "WARNING: some apps didn't start, run: docker compose up -d"
  fi
  if [ "$kuma_running" = yes ]; then
    sleep 60   # Give the others a minute to wake, so Uptime Kuma doesn't report them down.
    docker compose start uptime-kuma || say "WARNING: uptime-kuma didn't start"
  fi
}
trap restart_apps EXIT

[ "$kuma_running" = yes ] && docker compose stop uptime-kuma   # First, so it doesn't see the others stop.
if [ -n "$to_stop" ]; then
  say "Stopping for a moment:$to_stop"
  docker compose stop -t 60 $to_stop
fi

say "Pass 2: copying what changed"
"${RSYNC[@]}" "${EXCLUDES[@]}" "$CONFIG_DIR/" "$STAGING/config/"

restart_apps

# The few settings that don't live in the config folder.
cp -p "$ENV_FILE" "$STAGING/extras/server.env"
owner="$(stat -c %U "$SERVER_DIR")"
crontab -l -u "$owner" > "$STAGING/extras/crontab-$owner.txt" 2>/dev/null || true
crontab -l > "$STAGING/extras/crontab-root.txt" 2>/dev/null || true

archive="$BACKUP_DIR/config-$(date +%F_%H%M).tar.gz"
say "Packing $archive"
tar -C "$STAGING" --numeric-owner -czf "$archive.part" config extras
mv "$archive.part" "$archive"
chmod 600 "$archive"

# Keep the newest $KEEP_DAYS backups. Sorting by name is sorting by date.
ls -1 "$BACKUP_DIR"/config-*.tar.gz | sort | head -n -"$KEEP_DAYS" | while read -r old; do
  say "Removing old $(basename "$old")"
  rm -f "$old"
done

size=$(du -h "$archive" | cut -f1)
count=$(ls -1 "$BACKUP_DIR"/config-*.tar.gz | wc -l)
say "Done: $(basename "$archive") is $size, $count backups kept"

if [ -n "$PUSH_URL" ]; then
  curl -fsS -m 10 --retry 6 --retry-delay 20 --retry-all-errors -o /dev/null "$PUSH_URL" || say "WARNING: couldn't reach Uptime Kuma"
fi
