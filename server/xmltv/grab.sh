#!/bin/sh
# Fetches the TV guide on a timer, like a paperboy dropping off a fresh TV listings page.
# Writes /config/guide/guide.xml, which Jellyfin reads (README.md step 22).

GRABBER="${XMLTV_GRABBER:-tv_grab_zz_sdjson}"
DAYS="${XMLTV_DAYS:-14}"
EVERY="${XMLTV_EVERY_HOURS:-12}"
CONF="$HOME/.xmltv/$GRABBER.conf"

mkdir -p /config/guide

while true; do
  if [ ! -f "$CONF" ]; then
    echo "No settings for $GRABBER yet. Run the one-time setup in README.md step 22, then restart this container."
  else
    echo "Fetching $DAYS days of listings with $GRABBER..."
    # Write to a spare file first, so Jellyfin never reads a half-written guide.
    if "$GRABBER" --quiet --days "$DAYS" --output /config/guide/guide.xml.new; then
      mv /config/guide/guide.xml.new /config/guide/guide.xml
      echo "Guide updated. Next fetch in $EVERY hours."
    else
      rm -f /config/guide/guide.xml.new
      echo "Fetch failed; keeping the old guide. Trying again in $EVERY hours."
    fi
  fi
  sleep "$((EVERY * 3600))"
done
