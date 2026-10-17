#!/bin/sh
# Fetches the TV guide on a timer, like a paperboy dropping off a fresh TV listings page.
# Collects every guide it's given, staples them into one file (merge.pl),
# and leaves /config/guide/guide.xml for Jellyfin (README.md step 22).

PLAYLISTS="${XMLTV_PLAYLISTS:-}"
URLS="${XMLTV_GUIDE_URLS:-}"
GRABBER="${XMLTV_GRABBER:-}"
DAYS="${XMLTV_DAYS:-14}"
EVERY="${XMLTV_EVERY_HOURS:-12}"
PARTS=/config/parts
# Shared with the iptv-epg container: we leave batches of channels in channels/, it leaves one guide
# per batch in guides/ (same file names).
IPTV=/config/iptv-org

mkdir -p /config/guide "$PARTS" "$IPTV"
# Left over from before the channels were split into batches.
rm -f "$IPTV/channels.xml" "$IPTV/guide.xml" "$PARTS/iptv-org.xml"

while true; do
  # 0. M3U playlists from iptv-org: work out which websites have listings for their channels,
  #    and leave that list for the iptv-epg container, which builds the guide (README.md step 22).
  if [ -n "$PLAYLISTS" ]; then
    m=0; lists=""
    for url in $PLAYLISTS; do
      m=$((m + 1))
      echo "Fetching playlist $m: $url"
      curl -fsSL --retry 3 -o "$IPTV/playlist$m.m3u" "$url" && lists="$lists $IPTV/playlist$m.m3u"
    done
    echo "Fetching iptv-org's list of which website has each channel's listings..."
    rm -rf "$IPTV/channels.new"
    if [ -n "$lists" ] && curl -fsSL --retry 3 -o "$IPTV/guides.json" https://iptv-org.github.io/api/guides.json \
       && perl /usr/local/bin/make-channels.pl "$IPTV/guides.json" "$IPTV/channels.new" $lists; then
      rm -rf "$IPTV/channels" && mv "$IPTV/channels.new" "$IPTV/channels"
    else
      rm -rf "$IPTV/channels.new"
      echo "Couldn't update the iptv-org channel list; keeping the last one."
    fi
    # The guides iptv-epg built last time it ran, one per batch.
    rm -f "$PARTS"/iptv-org-*.xml
    for g in "$IPTV"/guides/*.xml; do
      [ -s "$g" ] && cp "$g" "$PARTS/iptv-org-$(basename "$g")"
    done
  fi

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
  #    A single guide just gets copied: reading a big one into memory to "combine" it with nothing is slow.
  set -- "$PARTS"/*.xml
  if [ -f "$1" ]; then
    if { [ $# -eq 1 ] && cp "$1" /config/guide/guide.xml.new; } \
       || { [ $# -gt 1 ] && perl /usr/local/bin/merge.pl /config/guide/guide.xml.new "$@"; }; then
      mv /config/guide/guide.xml.new /config/guide/guide.xml
      echo "Guide updated from $# source(s). Next update in $EVERY hours."
    else
      rm -f /config/guide/guide.xml.new
      echo "Couldn't combine the guides; keeping the old one."
    fi
  else
    echo "No guide yet. If you just started iptv-epg, it's still building one (README.md step 22)."
  fi

  sleep "$((EVERY * 3600))"
done
