#!/bin/sh
# Fetches the TV guide on a timer, like a paperboy dropping off a fresh TV listings page.
# Collects every guide it's given, staples them into one file with XMLTV's own Perl library (merge.pl),
# and leaves /config/guide/guide.xml for Jellyfin (README.md step 22).

URLS="${XMLTV_GUIDE_URLS:-}"
GRABBER="${XMLTV_GRABBER:-}"
DAYS="${XMLTV_DAYS:-14}"
EVERY="${XMLTV_EVERY_HOURS:-12}"
PARTS=/config/parts

mkdir -p /config/guide "$PARTS"

while true; do
  # 1. Guides published online, usually by the same people who make the M3U playlist.
  n=0
  for url in $URLS; do
    n=$((n + 1))
    echo "Fetching guide $n: $url"
    if curl -fsSL --retry 3 -o "$PARTS/$n.download" "$url"; then
      # Some guides come zipped (.gz). Unzip those; leave plain ones alone.
      if gzip -t "$PARTS/$n.download" 2>/dev/null; then
        gunzip -c "$PARTS/$n.download" > "$PARTS/$n.xml.new"
      else
        mv "$PARTS/$n.download" "$PARTS/$n.xml.new"
      fi
      mv "$PARTS/$n.xml.new" "$PARTS/$n.xml"
    else
      # Keep yesterday's copy rather than leave a hole in the guide.
      echo "Couldn't fetch guide $n; keeping the last copy, if there is one."
    fi
    rm -f "$PARTS/$n.download"
  done
  # Forget guides for links you've since removed from the list.
  for old in "$PARTS"/[0-9]*.xml; do
    [ -f "$old" ] || continue
    num=$(basename "$old" .xml)
    [ "$num" -gt "$n" ] && rm -f "$old"
  done

  # 2. Optional: an XMLTV grabber, for listings that aren't published as a file (README.md step 22g).
  if [ -n "$GRABBER" ]; then
    if [ -f "$HOME/.xmltv/$GRABBER.conf" ]; then
      echo "Running $GRABBER for $DAYS days..."
      "$GRABBER" --quiet --days "$DAYS" --output "$PARTS/grabber.xml.new" \
        && mv "$PARTS/grabber.xml.new" "$PARTS/grabber.xml"
    else
      echo "$GRABBER has no settings yet. Run its one-time setup (README.md step 22g)."
    fi
  fi

  # 3. Staple the pieces into one guide. Write a spare file first, so Jellyfin never reads half a guide.
  set -- "$PARTS"/*.xml
  if [ -f "$1" ]; then
    if perl /usr/local/bin/merge.pl /config/guide/guide.xml.new "$@"; then
      mv /config/guide/guide.xml.new /config/guide/guide.xml
      echo "Guide updated from $# source(s). Next update in $EVERY hours."
    else
      rm -f /config/guide/guide.xml.new
      echo "Couldn't combine the guides; keeping the old one."
    fi
  else
    echo "No guides yet. Set XMLTV_GUIDE_URLS in .env (README.md step 22)."
  fi

  sleep "$((EVERY * 3600))"
done
