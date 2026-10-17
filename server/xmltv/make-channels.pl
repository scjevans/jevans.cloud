#!/usr/bin/perl
# Writes the shopping list for iptv-org's guide builder: for every channel in your M3U playlists,
# which website has its listings. iptv-org keeps that matchup in guides.json.
# The list is split into batches (01.xml, 02.xml, ...) in OUTDIR, because iptv-epg keeps everything it
# grabs in memory until the end, and 800 channels at once runs it out of memory. Set the batch size
# with XMLTV_BATCH_SIZE (default 50).
# Usage: make-channels.pl GUIDES_JSON OUTDIR PLAYLIST...
use strict;
use warnings;
use JSON;

my ($guides_file, $outdir, @playlists) = @ARGV;
@playlists or die "usage: make-channels.pl GUIDES_JSON OUTDIR PLAYLIST...\n";
my $batch = $ENV{XMLTV_BATCH_SIZE} || 50;

open(my $gf, '<:raw', $guides_file) or die "make-channels.pl: can't read $guides_file: $!\n";
my $guides = decode_json(do { local $/; <$gf> });
close($gf);

# Every site that has listings for a channel, by channel id (like "ABC.us").
my %by_channel;
for my $g (@$guides) {
  next unless defined $g->{channel} && $g->{site} && defined $g->{site_id};
  push @{ $by_channel{ $g->{channel} } }, $g;
}

# Channels in the playlists. Their tvg-id is "Channel.cc", or "Channel.cc@Feed" for one feed of it.
my (%name, @ids);
for my $p (@playlists) {
  open(my $pf, '<:encoding(UTF-8)', $p) or die "make-channels.pl: can't read $p: $!\n";
  while (my $line = <$pf>) {
    next unless $line =~ /^#EXTINF/ && $line =~ /tvg-id="([^"]+)"/;
    my $id = $1;
    next if exists $name{$id};
    my ($n) = $line =~ /,\s*([^,]*?)\s*$/;
    $name{$id} = $n // $id;
    push @ids, $id;
  }
  close($pf);
}

# Best match first: the same feed, then a guide for the whole channel, then any; English preferred.
sub score {
  my ($g, $feed) = @_;
  my $s = 0;
  $s += 4 if defined $feed && defined $g->{feed} && $g->{feed} eq $feed;
  $s += 2 if !defined $g->{feed};
  $s += 1 if ($g->{lang} // '') eq 'en';
  return $s;
}

sub esc { my $t = shift; $t =~ s/&/&amp;/g; $t =~ s/</&lt;/g; $t =~ s/>/&gt;/g; $t =~ s/"/&quot;/g; return $t }

my @rows;
my $total = 0;
for my $id (@ids) {
  my ($channel, $feed) = split /@/, $id, 2;
  my $list = $by_channel{$channel} or next;
  my ($best) = sort { score($b, $feed) <=> score($a, $feed) } @$list;
  push @rows, [$best->{site}, sprintf(qq{  <channel site="%s" lang="%s" xmltv_id="%s" site_id="%s">%s</channel>\n},
    esc($best->{site}), esc($best->{lang} // 'en'), esc($id), esc($best->{site_id}), esc($name{$id}))];
}

# Channels from the same website go in the same batch where they can, so each website is visited
# by as few batches as possible.
@rows = map { $_->[1] } sort { $a->[0] cmp $b->[0] } @rows;

mkdir $outdir or die "make-channels.pl: can't make $outdir: $!\n";
my $batches = 0;
while (my @part = splice(@rows, 0, $batch)) {
  $batches++;
  my $out = sprintf('%s/%02d.xml', $outdir, $batches);
  open(my $fh, '>:encoding(UTF-8)', $out) or die "make-channels.pl: can't write $out: $!\n";
  print $fh qq{<?xml version="1.0" encoding="UTF-8"?>\n<channels>\n}, @part, "</channels>\n";
  close($fh) or die "make-channels.pl: can't finish $out: $!\n";
  $total += @part;
}

printf "%d channels in the playlists, %d with a known guide, in %d batches.\n", scalar(@ids), $total, $batches;
