#!/usr/bin/perl
# Combines several XMLTV guide files into one: every channel first, then every programme.
# tv_cat can't do this when a second file starts with its channel list, because by then
# it has already written the first file's programmes, and XMLTV puts all channels at the top.
# Reads one file at a time and copies the pieces straight across, so a big guide doesn't need
# much memory: like photocopying pages from each binder rather than retyping them all.
# Usage: merge.pl OUTPUT INPUT...
use strict;
use warnings;
use Encode qw(decode encode);

my $out = shift @ARGV or die "usage: merge.pl OUTPUT INPUT...\n";
@ARGV or die "merge.pl: no input files\n";

# One whole file, as UTF-8 (the odd guide is in another encoding; convert those).
sub slurp {
  my $file = shift;
  open(my $fh, '<:raw', $file) or die "merge.pl: can't read $file: $!\n";
  my $xml = do { local $/; <$fh> };
  close($fh);
  my ($enc) = $xml =~ /\A(?:\xEF\xBB\xBF)?\s*<\?xml[^>]*encoding=["']([^"']+)/;
  $xml = encode('UTF-8', decode($enc, $xml)) if $enc && $enc !~ /^utf-?8$/i;
  return $xml;
}

open(my $fh, '>:raw', $out) or die "merge.pl: can't write $out: $!\n";

# The <tv> tag at the top keeps the first guide's details (who made it).
my ($tv) = slurp($ARGV[0]) =~ /(<tv\b[^>]*?)\/?>/;
print $fh qq{<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE tv SYSTEM "xmltv.dtd">\n}, ($tv // '<tv'), ">\n";

# First pass: channels, each id once. Second pass: programmes.
my (%seen, $channels, $programmes);
for my $file (@ARGV) {
  my $xml = slurp($file);
  while ($xml =~ /(<channel\b(?:[^>]*\/>|.*?<\/channel>))/gs) {
    my $c = $1;
    my ($id) = $c =~ /^<channel\b[^>]*\bid=["']([^"']*)/;
    next if defined $id && $seen{$id}++;
    print $fh "  $c\n";
    $channels++;
  }
}
for my $file (@ARGV) {
  my $xml = slurp($file);
  while ($xml =~ /(<programme\b(?:[^>]*\/>|.*?<\/programme>))/gs) {
    print $fh "  $1\n";
    $programmes++;
  }
}

print $fh "</tv>\n";
close($fh) or die "merge.pl: can't finish $out: $!\n";

printf "Combined %d channels and %d programmes.\n", $channels // 0, $programmes // 0;
