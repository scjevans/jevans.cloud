# XMLTV's grabbers, from Debian's own package, in a small box.
# The grabbers are Perl scripts; the extra packages are what the Schedules Direct one needs to run.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      xmltv-util \
      ca-certificates \
      libwww-perl liblwp-protocol-https-perl libjson-perl libdatetime-perl libtry-tiny-perl \
 && rm -rf /var/lib/apt/lists/*

COPY grab.sh /usr/local/bin/grab.sh

CMD ["sh", "/usr/local/bin/grab.sh"]
