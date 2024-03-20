#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# xpm-remap-to-bmp.pl
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2024 Tomi Ollila
#	    All rights reserved
#
# Created: Mon 18 Mar 2024 19:46:49 +0200 too
# Last modified: Wed 20 Mar 2024 22:58:37 +0200 too

use 5.8.1;
use strict;
use warnings;

$ENV{'PATH'} = '/no//path/';

$_ = $0, s:.*/::, die qq(\nUsage: $0 ifile.xpm mapfile ofile.bmp

use mapfile to remap colors of an xpm file and write a bmp file.
"the use case" is to add partial transparencies to images.

sample usage:
   convert image file to an xpm file
   look into that .xpm to see there is just a few colors
   create empty 'mapfile'
   execute  $_ ifile.xpm mapfle ofile.bmp
   use error message output to fill mapfile
   execute  $_ ifile.xpm mapfle ofile.bmp
   view ofile.bmp using an image viewer that works...

mapfile format samples:

  ; or / -- comment up to the end of line
  color-in-xpm  #RRGGBBAA
  color-in-xpm  RR GG BB AA\n\n) unless @ARGV == 3;

my ($ifile, $mapfile, $ofile) = @ARGV;

die "'$ifile': no such file\n" unless -f $ifile;
die "'$mapfile': no such file\n" unless -f $mapfile;
die "'$ofile exists\n", if -e $ofile;
my $owip = "$ofile.wip";
die "'$owip exists\n", if -e $owip;

my %map;

open I, '<', $mapfile or die "Cannot open $mapfile: $!\n";
while (<I>) {
    s|[;/].*||; # ; or / starts "comment"
    next if /^\s*$/;
    /^\s*(\S+)\s+(.*)/;
    my ($s, $d) = ($1, $2);
    $d =~ s/\s+//g;
    $d =~ /^#?([\dA-Fa-f]{8})$/ or
      die "$mapfile line $.: '$d' not [#]RRBBGGAA\n";
    $d = $1;
    $map{$s} = pack 'N', hex($d)
}
close I;
#use Data::Dumper; print Dumper \%map; exit;

open I, '<', $ifile or die "Cannot open $ifile: $!\n";
my ($cols, $rows, $colors, $cpp);
while (<I>) {
    next unless /^\s*"\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/;
    ($cols, $rows, $colors, $cpp) = ($1, $2, $3, $4);
    last
}
die "Cannot find header in $ifile\n" unless defined $cols;
die "At the moment, only 1 'char-per-pixel' supported\n"
  unless $cpp == 1;

my %omap;
my $ev = 0;
while (<I>) {
    last unless /^\s*"(.).*\sc\s+([^\s"]+)/; # XXX: spaces in X11 color names
    my $mapcolor = $map{$2};
    $ev = 1, warn "$2  RR GG BB AA ; mapping missing in '$mapfile'\n"
      unless defined $mapcolor;
    $omap{$1} = $mapcolor;
}
die "Use the above 'hints' to update '$mapfile'\n" if $ev;

my @rows;
while (<I>) {
    next unless /^\s*"(.*?)"/;
    my $l = length $1;
    die "$ifile line $.: expected $cols pixel chars, read $l chars\n"
      unless $l == $cols;
    my @l = map { $omap{$_} } split //, $1;
    #print @l; # | od -tx4
    push @rows, join '',@l;
}
close I;
die "$ifile: expected $rows pixel lines, read ", scalar @rows, " lines\n"
  unless @rows == $rows;

eval 'END { unlink $owip if defined $owip }';
open O, '>', $owip || die "Cannot open '$owip'\n";

my $size = $cols * $rows * 4;

# bmp header:        wh     s    rgba
print O pack 'ccVx4VVVVcxcxVVVVx8VVVVccccx48',
  0x42, 0x4d, 122 + $size, 122, 108, $cols, $rows, 1, 32, 3, $size,
  2835, 2835, 0xff, 0xff << 8, 0xff << 16, 0xff << 24, 0x20, 0x6e, 0x69, 0x57;

print O $_ foreach (reverse @rows);
close O or die $!;

rename $owip, $ofile;
undef $owip;
print "Wrote '$ofile'\n"
