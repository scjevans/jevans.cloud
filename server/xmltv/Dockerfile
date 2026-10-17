# XMLTV's grabbers, from Debian's own package, in a small box.
# XMLTV's library and grabbers are Perl. merge.pl uses the library to combine guides. curl fetches guides from the internet;
# the Perl packages are what the Schedules Direct grabber needs, if you ever use it.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      xmltv-util \
      ca-certificates curl \
      libwww-perl liblwp-protocol-https-perl libjson-perl libdatetime-perl libtry-tiny-perl \
 && rm -rf /var/lib/apt/lists/*

COPY grab.sh merge.pl /usr/local/bin/

CMD ["sh", "/usr/local/bin/grab.sh"]
