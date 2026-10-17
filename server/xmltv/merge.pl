#!/usr/bin/perl
# Combines several XMLTV guide files into one: every channel first, then every programme.
# tv_cat can't do this when a second file starts with its channel list, because by then
# it has already written the first file's programmes, and XMLTV puts all channels at the top.
# Usage: merge.pl OUTPUT INPUT...
use strict;
use warnings;
use XMLTV;

my $out = shift @ARGV or die "usage: merge.pl OUTPUT INPUT...\n";
@ARGV or die "merge.pl: no input files\n";

# Reads every file into memory and merges them: channels joined by id, programmes kept in order.
my $data = XMLTV::parsefiles(@ARGV);

open(my $fh, '>', $out) or die "merge.pl: can't write $out: $!\n";
XMLTV::write_data($data, OUTPUT => $fh);
close($fh) or die "merge.pl: can't finish $out: $!\n";

printf "Combined %d channels and %d programmes.\n", scalar(keys %{$data->[2]}), scalar(@{$data->[3]});
