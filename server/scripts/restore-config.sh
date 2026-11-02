#!/bin/bash
# Puts one app's settings back from a nightly backup (README.md step 30e).
#
# It asks two questions (which night, which app), then: stops that app, moves its current
# folder aside (nothing is deleted, so you can always go back), unpacks the backup in its
# place, and starts the app again. Run it with sudo.

set -euo pipefail

SERVER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SERVER_DIR/.env"
env_value() { grep "^$1=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d "'\"" || true; }

CONFIG_DIR="$(env_value CONFIG_DIR)"
BACKUP_DIR="$(env_value BACKUP_DIR)"; BACKUP_DIR="${BACKUP_DIR:-/data/backups/config}"

[ "$(id -u)" = 0 ] || { echo "Run it with sudo."; exit 1; }
[ -n "$CONFIG_DIR" ] && [ -d "$CONFIG_DIR" ] || { echo "CONFIG_DIR in $ENV_FILE is missing."; exit 1; }

mapfile -t backups < <(ls -1 "$BACKUP_DIR"/config-*.tar.gz 2>/dev/null | sort -r)
[ "${#backups[@]}" -gt 0 ] || { echo "No backups in $BACKUP_DIR yet."; exit 1; }

echo "Backups, newest first:"
for i in "${!backups[@]}"; do
  printf '  %2d) %s  (%s)\n' $((i + 1)) "$(basename "${backups[$i]}")" "$(du -h "${backups[$i]}" | cut -f1)"
done
read -rp "Which one? (number, Enter = 1) " n
n="${n:-1}"
[[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#backups[@]}" ] || { echo "No such number."; exit 1; }
archive="${backups[$((n - 1))]}"

mapfile -t apps < <(tar -tzf "$archive" | awk -F/ '$1 == "config" && $2 != "" {print $2}' | sort -u)
echo "Apps in $(basename "$archive"):"
for i in "${!apps[@]}"; do printf '  %2d) %s\n' $((i + 1)) "${apps[$i]}"; done
read -rp "Which app? (number) " n
[[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#apps[@]}" ] || { echo "No such number."; exit 1; }
app="${apps[$((n - 1))]}"

aside="$CONFIG_DIR/$app.before-restore-$(date +%F_%H%M)"
echo
echo "This will stop $app, move its folder to $aside,"
echo "put back the copy from $(basename "$archive"), and start $app again."
read -rp "Go ahead? (y/n) " yn
[ "$yn" = y ] || { echo "Nothing changed."; exit 0; }

cd "$SERVER_DIR"
docker compose stop "$app" 2>/dev/null || true
[ -e "$CONFIG_DIR/$app" ] && mv "$CONFIG_DIR/$app" "$aside"
tar -xzf "$archive" -C "$CONFIG_DIR" --numeric-owner --strip-components=1 "config/$app"
docker compose start "$app" 2>/dev/null || docker compose up -d "$app" 2>/dev/null || \
  echo "(No app called $app in docker-compose.yml to start: the folder is back, that's all.)"

echo
echo "Done. $app is back to how it was on $(basename "$archive" .tar.gz | cut -d- -f2-)."
echo "Its folder from just now is kept at $aside"
