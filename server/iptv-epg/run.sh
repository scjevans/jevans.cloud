#!/bin/sh
# Runs iptv-org's guide builder one batch of channels at a time, once a day (README.md step 22).
# It keeps everything it grabs in memory until it's done, and all ~800 channels at once ran it out
# of memory. Like the reporter calling 50 stations, filing that story, then starting on the next 50.
# Reads public/channels/NN.xml (written by xmltv), writes public/guides/NN.xml.

cd /epg || exit 1
CH=public/channels
OUT=public/guides
AT="${GRAB_AT:-02:00}"
mkdir -p "$OUT"

grab_all() {
  set -- "$CH"/*.xml
  i=0
  for f in "$@"; do
    i=$((i + 1))
    name=$(basename "$f")
    echo "$(date '+%F %T') Batch $i of $#..."
    if npm run grab --- --channels="$f" --output="$OUT/$name.new" \
         --days="${DAYS:-2}" --maxConnections="${MAX_CONNECTIONS:-10}" && [ -s "$OUT/$name.new" ]; then
      mv "$OUT/$name.new" "$OUT/$name"
    else
      rm -f "$OUT/$name.new"
      echo "Batch $i failed; keeping its last guide, if there is one."
    fi
  done
  # Forget guides for batches that no longer exist (the playlist got shorter).
  for g in "$OUT"/*.xml; do
    [ -f "$g" ] && [ ! -f "$CH/$(basename "$g")" ] && rm -f "$g"
  done
  echo "$(date '+%F %T') All $# batches done. Next run at $AT."
}

# First start: build a guide straight away, once xmltv has left the channel list.
if [ -z "$(ls "$OUT")" ]; then
  until [ -n "$(ls "$CH" 2>/dev/null)" ]; do
    echo "Waiting for xmltv to write the channel list (README.md step 22c)..."
    sleep 60
  done
  grab_all
fi

echo "Next run at $AT."
while true; do
  if [ "$(date +%H:%M)" = "$AT" ]; then
    grab_all
    sleep 60
  fi
  sleep 30
done
