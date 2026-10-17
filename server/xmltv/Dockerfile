# XMLTV's grabbers, from Debian's own package, in a small box.
# XMLTV's grabbers are Perl, and so are merge.pl, which combines guides, and make-channels.pl,
# which reads iptv-org's channel list (JSON). curl fetches guides from the internet;
# the Perl packages are what the Schedules Direct grabber needs, if you ever use it.
# libjson-xs-perl is the fast JSON reader: without it, iptv-org's big channel list takes many minutes to read.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      xmltv-util \
      ca-certificates curl \
      libwww-perl liblwp-protocol-https-perl libjson-perl libdatetime-perl libtry-tiny-perl \
      libjson-xs-perl \
 && rm -rf /var/lib/apt/lists/*

COPY grab.sh merge.pl make-channels.pl /usr/local/bin/

CMD ["sh", "/usr/local/bin/grab.sh"]
