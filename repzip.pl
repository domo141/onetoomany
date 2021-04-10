#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ repzip.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2019 Tomi Ollila
#	    All rights reserved
#
# Created: Sun 18 Aug 2019 18:53:07 EEST too (zipdir.pl)
# Created: Fri 21 Aug 2020 18:18:04 EEST too (custar.pl)
# Last modified: Sat 10 Apr 2021 20:29:57 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

use 5.8.1;
use strict;
use warnings;

use POSIX qw/mktime getcwd/;

$ENV{TZ} = 'UTC';

die "\nReproducible zip archives.
\nUsage: $0 zipname mtime [options] [--] dirs/files\n\n",
  "  mtime formats (in UTC):\n",
  "    yyyy-mm-dd  yyyy-mm-ddThh:mm:ss  yyyy-mm-dd+hh:mm:ss\n",
  "    yyyy-mm-dd+hh:mm  yyyy-mm-dd+hh  hh:mm  d  \@secs\n",
  "  hh:mm -- hour and min today,  d -- number of days ago 00:00\n\n",
  " options:\n",
  "    -C           -- change to directory before adding files\n",
  "   --exclude     -- glob patterns of files to exclude\n\n",
  unless @ARGV > 2;

my $of = shift;
my $gmtime = shift;

if ($gmtime =~ /^@(\d+)$/) {
    $gmtime = $1;
} elsif ($gmtime =~ /^(\d\d?):(\d\d)$/) {
    $gmtime = time;
    $gmtime = $gmtime - $gmtime % 86400 + $1 * 3600 + $2 * 60;
} elsif ($gmtime =~ /^\d$/) {
    $gmtime = time - 86400 * $gmtime;
    $gmtime = $gmtime - $gmtime % 86400
} elsif ($gmtime =~
	 /(20\d\d)-([01]\d)-([0-3]\d)$/) {
    $gmtime = mktime(0, 0, 0, $3, $2 - 1, $1 - 1900)
} elsif ($gmtime =~
	 /(20\d\d)-([01]\d)-([0-3]\d)\+([012]\d)$/) {
    $gmtime = mktime(0, 0, $4, $3, $2 - 1, $1 - 1900)
} elsif ($gmtime =~
	 /(20\d\d)-([01]\d)-([0-3]\d)\+([012]\d):([0-5]\d)$/) {
    $gmtime = mktime(0, $5, $4, $3, $2 - 1, $1 - 1900)
} elsif ($gmtime =~
	 /(20\d\d)-([01]\d)-([0-3]\d)[+T]([012]\d):([0-5]\d):([0-5]\d)$/) {
    $gmtime = mktime($6, $5, $4, $3, $2 - 1, $1 - 1900)
}
else { die "'$gmtime': unknown time format\n" }

#my $time_date = "\x00\x00\x0f\x4f"; # 2019-08-15 00:00:00
#                                    # ((2019 - 1980) << 9) + (8 << 5) + 15
my $time_date;
{
 my @lt = gmtime $gmtime;
 die "Cannot handle dates after year 2105 (yet)\n" if $lt[5] >= 205;

 # dos date: 5 bits day, 4 bits month, 7 bits year (1980 + 127 max)
 # dos time: 5 bits secs (/2), 6 bits minutes, 5 bits hour

 my $date = (($lt[5] - 80) << 9) + (($lt[4] + 1) << 5) + $lt[3];
 my $time = ($lt[2] << 11) + ($lt[1] << 5) + int($lt[0] / 2);

 $time_date = pack 'vv', $time, $date
}

my @excludes;
my $tcwd; # one global, no order-sensitivity (at least for now)

while (@ARGV) {
    shift, last if $ARGV[0] eq '--';
    last unless $ARGV[0] =~ /^-/;
    $_ = shift;
    if ($_ eq '-C') {
	die "No value for '$_'\n" unless @ARGV;
	$tcwd = shift;
	next
    }
    if ($_ =~ /^-C(.*)/) {
	$tcwd = $1;
	next
    }
    if ($_ eq '--exclude') {
	die "No value for '$_'\n" unless @ARGV;
	push @excludes, shift;
	next
    }
    if ($_ =~ /^--exclude=(.*)/) {
	push @excludes, $1;
	next
    }
    die "'$_': unknown option\n"
}

die "No files/dirs\n" unless @ARGV;

my $swd;
if (defined $tcwd) {
    # note: dirhandles, play with first to get understanding...
    die "'$tcwd': not a directory\n" unless -d $tcwd;
    $swd = getcwd
    #... alternative, openat(2)...
}
foreach (@excludes) {
    # good enough? glob-to-re conversion ?
    $_ = "^$_" unless s/^[*]+//;
    $_ = "$_\$" unless s/[*]+$//;
    s/[.]/[.]/g; s/[*]/.*/g; s/[?]/./g;
    $_ = qr/$_/
}
push @excludes, qr/^..?$/;

sub include()
{
    foreach my $re (@excludes) { return 0 if $_ =~ $re }
    1
}

my (@files, %hash, $ca);

sub add_dir($);
sub add_dir($)
{
    opendir my $dh, $_[0] or die "Opening dir '$_[0]': $!\n";
    my @df = sort grep { include } readdir $dh;
    closedir $dh;

    foreach (@df) {
	my $de = "$_[0]/$_";
	lstat $de;
	next if -l _;
	if (-d _) {
	    add_dir $de;
	    next
	}
	if (-f _) {
	    my $seen = $hash{$_} || '';
	    die "'$de': found following '$seen' and '$de'\n" if $seen;
	    $hash{$de} = $ca;
	    push @files, $de;
	    next
	}
	next if -e _;
	warn "internal problem: file '$de' not found\n"
    }
}

if (defined $tcwd) {
    chdir $tcwd or die "Cannot chdir to '$tcwd'. $!\n"
}

if (@ARGV eq 1 && $ARGV[0] eq '.') {
    add_dir '.'; # zip(1) drops leading ./ (at least when I tested)
    shift @ARGV
}
for (@ARGV) {
    die("'$_': suspicious path\n") if m,(?:^|/)\.\.?(?:/|$),;
    lstat;
    next if -l _;
    if (-d _) {
	$ca = $_;
	s:/+$::;
	add_dir $_;
	next
    }
    if (-f _) {
	my $seen = $hash{$_} || '';
	die "'$_': found following '$seen' and '$_'\n" if $seen;
	$hash{$_} = $_;
	push @files, $_;
	next
    }
    next if -e _;
    die "'$_': no such file or directory\n"
}

die "No files to archive\n" unless @files;

%hash = ();

$of = "$swd/$of" if defined $swd and $of !~ /^\//;

my $owip;
END { return unless defined $owip; chdir $swd if defined $swd; unlink $owip }

$owip = "$of.wip";

# fixme: stream zip output (pipe and fork) then fix date & time in memory

open P, '|-', qw/zip -X -nw -@/, $owip or die $!;
print P join("\n", @files), "\n";
close P or die $!;

print "Modifying dates...\n";
open I, '+<', "$owip" or die $!;

my $o = 0;
while (1) {
    last if ((sysread I, $_, 34) < 34);
    if ((substr $_, 0, 4) eq "\x50\x4b\x03\x04") {
	# local file header
	my ($cs, $_i, $fl, $el) = unpack "x[18] V V v v";
	#print "- $o $cs, $fl, $el\n";
	sysseek I, $o + 10, 0 or die $!;
	syswrite I, $time_date;
	$o = $o + $cs + $fl + $el + 30;
	sysseek I, $o, 0 or die $!;
	next
    }
    if ((substr $_, 0, 4) eq "\x50\x4b\x01\x02") {
	# cental directory header
	my ($fl, $el, $kl) = unpack "x[28] v v v";
	#print "= $o $fl, $el, $kl\n";
	sysseek I, $o + 12, 0 or die $!;
	syswrite I, $time_date;
	$o = $o + $fl + $el + $kl + 46;
	sysseek I, $o, 0 or die $!;
	next
    }
    die "Unknown hdr at $o\n"
}

# end of central directory record
unless ((substr $_, 0, 4) eq "\x50\x4b\x05\x06") {
    die "Unexpected content at $o \n"
}
close I;
print "All done\n";

rename $owip, $of;
undef $owip
