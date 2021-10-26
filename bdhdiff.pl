#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ bdhdiff.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2021 Tomi Ollila
#	    All rights reserved
#
# Created: Mon 25 Oct 2021 19:17:16 EEST too
# Last modified: Tue 26 Oct 2021 23:39:06 +0300 too

use 5.8.1;
use strict;
use warnings;
use POSIX;

die "\nBinary Dump-Hex Diff

Usage: $0 file1 file2\n\n" unless @ARGV == 2;

pipe R1, W1 or die;
pipe R2, W2 or die;

open I1, '<', $ARGV[0] or die;
open I2, '<', $ARGV[1] or die;

pipe R3, W3 or die;

if (fork == 0) {
    # exec'ing here so close-on-exec effective
    POSIX::dup2(fileno(R1), 3); # no close-on-exec
    POSIX::dup2(fileno(R2), 4); # ditto
    open STDOUT, '>&', W3 or die $!;
    exec qw'diff -U16 /dev/fd/3 /dev/fd/4';
    die 'not reached'
}

close R1;
close R2;

if (fork == 0) {
    close W1; close W2; close W3; close I1; close I2;
    #print $_ while (<R3>); exit 0;
    $_ = <R3>;
    $_ = <R3>;
    $_ = <R3>;
    die unless /^@@ -(\d+),(\d+) [+](\d+),(\d+) /;
    my %hash;
    $hash{sprintf("%02x", $_)} = '.' for (0..31, 127..255);
    $hash{sprintf("%02x", $_)} = chr($_) for (32..126);
    my @cap;
    my $ns;
    sub hexdump16() {
	print $ns, "@cap[0..7]  @cap[8..15]   ";
	print $hash{$_} for (@cap);
	print "\n";
	@cap = ()
    }
    sub hexdump() {
	if (@cap < 9) { print $ns, "@cap    " }
	else { print $ns, "@cap[0..7]  @cap[8..$#cap]   " }
	print "   " x (16 - @cap);
	print $hash{$_} for (@cap);
	print "\n";
	@cap = ()
    }
    my $cap = '';
    my ($nrl, $nrr);
    sub at() {
	hexdump if @cap;
	# XTERM control sequences, good enough(?) (tput setaf <n>, tput sgr0)
	($nrl, $nrr) = ($1 - 1, $3 - 1);
	printf "\033[36m@@ -:$nrl(0x%x),$2b +:$nrr(0x%x),$4b @@\n", $nrl, $nrr;
	$cap = '' # [36m above -- cyan
    }
    at;
    sub cap($$$) {
	if ($_[0] ne $cap) {
	    hexdump if @cap;
	    print "\033[$_[2]m";
	    $cap = $_[0];
	    if ($cap eq '-')    { $ns = sprintf('%8x  -', $nrl) }
	    elsif ($cap eq '+') { $ns = sprintf('%8x  -', $nrr) }
	    else { $ns = ' ' x 11 }
	}
	if ($cap eq '-')    { $nrl++ }
	elsif ($cap eq '+') { $nrr++ }
	else { $nrl++; $nrr++ }
	push @cap, $_[1];
	hexdump16 if @cap == 16
    }
    while (<R3>) {
	at, next if /^@@ -(\d+),(\d+) [+](\d+),(\d+) /;
	/^(.)(\w+)/;
	cap($1, $2, '31'), next if $1 eq '-';  # '[31m' - red
	cap($1, $2, '32'), next if $1 eq '+';  # '[32m' - green
	cap($1, $2, ''),   next if $1 eq ' ';  # '[m'   - sgr0
	die 'not reached'
    }
    hexdump if @cap;
    print "\033[m";
    exit 0
}

close R3;
close W3;

# data feeders

$" = "\n";

if (fork == 0) {
    close W2; close I2;
    while (1) {
	my $l1 = read I1, $_, 8192;
	last unless $l1;
	my @l = unpack("H2" x $l1, $_);
	print W1 "@l", "\n"
    }
    close W1;
    exit 0
}

close W1;
close I1;

while (1) {
    my $l2 = read I2, $_, 8192;
    last unless $l2;
    my @l = unpack("H2" x $l2, $_);
    print W2 "@l", "\n"
}

close W2;
close I2;

wait;
wait;
wait;
