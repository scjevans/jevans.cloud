#!/bin/sh
# Tells Uptime Kuma "the media drive is here" once a minute (README.md step 22e).
# Like a night guard pressing a button on each round: if the presses stop, the alarm goes off.
# Cron runs it every minute. It only presses when /data is mounted AND the drive behind it still
# exists, so an unplugged drive (or a server that never mounted it) means silence, and Uptime Kuma
# buzzes your phone.

env_file="$(dirname "$0")/../.env"
url=$(grep '^MEDIA_DRIVE_PUSH_URL=' "$env_file" | cut -d= -f2- | tr -d "'\"")
[ -n "$url" ] || exit 0

# When a USB drive drops off, /data can stay listed as mounted for a while; its device file vanishes at once.
mountpoint -q /data && [ -b "$(findmnt -no SOURCE /data)" ] || exit 0

curl -fsS -m 10 -o /dev/null "$url"
