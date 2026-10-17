# XMLTV's grabbers, from Debian's own package, in a small box.
# tv_cat (which combines guides) and the grabbers are Perl scripts. curl fetches guides from the internet;
# the Perl packages are what the Schedules Direct grabber needs, if you ever use it.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      xmltv-util \
      ca-certificates curl \
      libwww-perl liblwp-protocol-https-perl libjson-perl libdatetime-perl libtry-tiny-perl \
 && rm -rf /var/lib/apt/lists/*

COPY grab.sh /usr/local/bin/grab.sh

CMD ["sh", "/usr/local/bin/grab.sh"]
