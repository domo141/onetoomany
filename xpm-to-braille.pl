#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ xpm-to-braille.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2022 Tomi Ollila
#	    All rights reserved
#
# Created: Wed 09 Dec 2015 19:02:24 EET too  (as bdfbits-braille.pl)
# Created: Sat 25 Jun 2022 12:14:16 EEST too
# Last modified: Sat 25 Jun 2022 14:38:58 +0300 too

use 5.8.1;
use strict;
use warnings;

my $reverse_colors = 0;
my $remove_trailing_whitespace = 1;
my $output_file = '';

while (@ARGV) {
    $reverse_colors = 1 if $ARGV[0] =~ /^-.*r/;
    $remove_trailing_whitespace = 0 if $ARGV[0] =~ /^-.*k/;

    if ($ARGV[0] eq '-o') {
	die "$0: '-o' needs an argument\n" unless @ARGV > 1;
	$output_file = $ARGV[1]; shift @ARGV; shift @ARGV; next
    }
    if ($ARGV[0] =~ /^-o(.+)/) {
	$output_file = $1, shift @ARGV, next
    }
    last unless $ARGV[0] =~ /^-./;
    $ARGV[0] =~ tr/-rk//d;
    die "$0: '$ARGV[0]': unknown option(s)\n" if $ARGV[0];
    shift
}
die "Usage: $0 [-rk] [-o output-file] (input-file | '-')\n" unless @ARGV == 1;

if ($ARGV[0] eq '-') {
    open I, '<&', \*STDIN or die;
}
else {
    open I, '<', $ARGV[0] or die "$0: $ARGV[0]: $!\n";
}

if ($output_file) {
    open O, '>:utf8', $output_file or die "$0: '$output_file': $!\n";
    select O;
}
else {
    binmode STDOUT, ':utf8';
}
my @l;
my ($pxb, $pxf);

# http://www.alanwood.net/unicode/braille_patterns.html
# https://github.com/asciimoo/drawille

sub brout()
{
    my @s = (0) x 512;
    my ($l, $c, $mc); $mc = 0;
    $c = 0; $l = (shift @l) . '"';
    while ($l =~ s/(.)(.)//) {
	$s[$c++] |= ($1 eq $pxf) * 1 + ($2 eq $pxf) * 8;
    }
    $mc = $c if $mc < $c;
    $c = 0; $l = (shift @l || '') . '"';
    while ($l =~ s/(.)(.)//) {
	$s[$c++] |= ($1 eq $pxf) * 2 + ($2 eq $pxf) * 16;
    }
    $mc = $c if $mc < $c;
    $c = 0; $l = (shift @l || '') . '"';
    while ($l =~ s/(.)(.)//) {
	$s[$c++] |= ($1 eq $pxf) * 4 + ($2 eq $pxf) * 32;
    }
    $mc = $c if $mc < $c;
    $c = 0; $l = (shift @l || '') . '"';
    while ($l =~ s/(.)(.)//) {
	$s[$c++] |= ($1 eq $pxf) * 64 + ($2 eq $pxf) * 128;
    }
    splice @s, $mc;
    if ($remove_trailing_whitespace) {
	pop @s while (@s && $s[$#s] == 0);
    }
    print chr(0x2800 + $_) for (@s);
    print "\n";
    @l = ();
}

while (<I>) {
    if (/^"(.) c (\w+)",/) {
	die "$0: Too many colors in $ARGV[0]\n"
	  if defined $pxb and defined $pxf;
	if ($2 eq 'None') {
	    $pxf = $pxb if defined $pxb;
	    $pxb = $1;
	    next
	}
	if (defined $pxb) { $pxf = $1 } else { $pxb = $1 }
	next
    }
    last if /[*]\s+pi[x]els\s+[*]/
}

die "$0: '$ARGV[0]': Not 2-color .xpm\n" unless defined $pxb and defined $pxf;

($pxb, $pxf) = ($pxf, $pxb) if $reverse_colors;

while (<I>)
{
    next unless /^"(.*)"/;
    push @l, $1;
    brout if @l == 4;
}
brout if @l;

close I;
exit $?;
