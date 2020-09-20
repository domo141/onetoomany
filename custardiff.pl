#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ custardiff.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2020 Tomi Ollila
#	    All rights reserved
#
# Created: Fri 11 Sep 2020 21:24:10 EEST too
# Last modified: Sun 20 Sep 2020 19:56:02 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

# hint: LC_ALL=C sh -c './custar.sh archive.tar.gz 2020-02-02 *'
# for archiving with shell wildcard (w/ custar.pl . gets close)

use 5.8.1;
use strict;
use warnings;

my @res;
my ($seek1, $seek2) = (0, 0);

sub needarg() { die "No value for '$_'\n" unless @ARGV }

my ($tarf1, $tarf2);

while (@ARGV) {
    shift, last if $ARGV[0] eq '--';
    unless ($ARGV[0] =~ /^-/) {
	$tarf1 = $ARGV[0], shift, next unless defined $tarf1;
	$tarf2 = $ARGV[0], shift, next unless defined $tarf2;
	die "$0: '$ARGV[0]': too many arguments\n"
    }
    $_ = shift;

    needarg, push(@res, shift), next if $_ eq '-s';
    needarg, $seek1 = (shift) + 0, next if $_ eq '--seek1';
    needarg, $seek2 = (shift) + 0, next if $_ eq '--seek2';

    push(@res, $1), next if $_ =~ /^-s(.*)/;
    $seek1 = $1 + 0, next if $_ =~ /^--seek1=(.*)/;
    $seek2 = $1 + 0, next if $_ =~ /^--seek2=(.*)/;

    die "'$_': unknown option"
}

die "Usage: $0 [options] tarchive1 tarchive2\n"
  unless defined $tarf2 and @ARGV == (defined $tarf1)? 1: 2;

die "'$tarf1': no such file\n" unless -f $tarf1;
die "'$tarf2': no such file\n" unless -f $tarf2;

sub xforms($); # fn name from custar.pl...
if (@res) {
    my $eval = 'sub xforms($) {';
    #
    # Current solution is to "eval" replace script run time. Due to input
    # restrictions full perl regexp substitution interface is not available
    # (';'s dropped, separator must be non-word character).
    # Improvements welcome.
    #
    foreach (@res) {
	# early checks...
	die "'$_' does not start with non-word character\n" unless /^\W/;
	my $p = substr($_, 0, 1);
	tr/;//d;
	my $s = substr($_, -1, 1);
	die "'$_' not $p...$p...$p nor $s...$s...$s\n" unless $p eq $s;
	$eval .= "\n \$_[0] =~ s$_;";
    }
    $eval .= "\n}; 1";
    eval $eval or die "Unsupported/broken '-s ...' content\n";
}

my %zc = ( '.tar' => '', '.tar.bzip2' => 'bzip2',
	   '.tar.gz' => 'gzip', '.tgz' => 'gzip',
	   '.tar.xz' => 'xz', '.txz' => 'xz',
	   '.tar.lz' => 'lzip', '.tlz' => 'lzip' );

sub fmz($$) {
    $_[1] =~ /\S((?:[.]tar)?[.]?[.]\w+)$/;
    die "Unknown format in '$_[1]': not in (fn" . join(', fn', sort keys %zc) .
  ")\n" unless defined $1 and defined ($_[0] = $zc{$1});
}
my ($zc1, $zc2);
fmz $zc1, $tarf1;
fmz $zc2, $tarf2;

sub opn($$$$) {
    if ($_[1]) { open $_[0], '-|', $_[1], '-dc', $_[3] or die $! }
    else       { open $_[0], '<', $_[3] or die $! }
    seek $_[0], $_[2], 0 if $_[2] > 0;
}
my ($fh1, $fh2);
opn $fh1, $zc1, $seek1, $tarf1;
opn $fh2, $zc2, $seek2, $tarf2;

sub unpack_ustar_hdr($$) {
    my @l = unpack('A100 A8 A8 A8 A12 A12 A8 A1 A100 a8 A32 A32 A8 A8 A155',
		   $_[0]);
    if ($l[14]) {
	$l[14] =~ s:/*$:/:;
	$l[0] = $l[14] . $l[0];
    }
    xforms $l[0] if @res;
    die "$_[1]: '$l[9]': not 'ustar{\\0}00'\n" unless $l[9] eq "ustar\00000";
    return ($l[0], $l[1]+0, $l[2]+0, $l[3]+0, oct($l[4]), oct($l[5]),
	    $l[7], $l[8], $l[10], $l[11], $l[12]+0, $l[13]+0, 1);
}

my (@h0, @h1);

sub chkdiffer($$) {
    if ($h0[$_[0]] ne $h1[$_[0]]) {
	print "$h0[0]: $_[1] differ ($h0[$_[0]] != $h1[$_[0]])\n";
	return 0
    }
    return 1
}

# return for filename / file content ....
sub hdrdiffer() {
    my $cmp = 1;
    chkdiffer  1, "file mode (perms)";
    chkdiffer  2, "user id";
    chkdiffer  3, "group id";
    chkdiffer  4, "file size" or $cmp = 0; # no point compare, but visual diff
    chkdiffer  5, "mod. time";
    chkdiffer  6, "file type" or $cmp = -1; # -1: no point ever diff
    chkdiffer  7, "link name" or $cmp = -1;
    chkdiffer  8, "user name";
    chkdiffer  9, "group name";
    chkdiffer 10, "device major";
    chkdiffer 11, "device minor";
    return -1 if $h0[6] != '0';
    return $cmp;
}

my ($pname0, $pname1) = ('', '');
my $z512 = "\0" x 512;

sub read_hdr($$$) {
    my $buf;
    while (1) {
	my $l = read $_[0], $buf, 512;
	die $! unless defined $l;
	if ($l == 512) {
	    next if $buf eq $z512;
	    last;
	}
	die "fixme" unless $l == 0;
	return ("\377\377", 0, 0, 0, 0, 0, '9', '', '', '', 0, 0, 0)
    }
    my @h = unpack_ustar_hdr $buf, $_[2];
    my $n = $h[0];
    die "order!: $_[2]: $_[1] > $n\n" unless $_[1] le $n;
    $_[1] = $n;
    return @h;
}

# btw: check/test if sysread is faster...
sub consume($$) {
    my $left = $_[1]; # could have used alias to list, but...
    $left = ($left + 511) & ~511;
    my $buf;
    while ($left > 1024 * 1024) {
	# xxx check read length (readfully?, check other perl code)
	read $_[0], $buf, 1024 * 1024;
	$left -= 1024 * 1024
    }
    if ($left > 0) {
	# ditto
	read $_[0], $buf, $left;
    }
}

sub compare() {
    my $left = ($h0[4] + 511) & ~511;
    my ($buf0, $buf1);
    my $diff = 0;
    while ($left > 1024 * 1024) {
	# xxx check read length (readfully?, check other perl code)
	read $fh1, $buf0, 1024 * 1024;
	read $fh2, $buf1, 1024 * 1024;
	$diff = $buf0 cmp $buf1 unless $diff;
	$left -= 1024 * 1024;
    }
    if ($left > 0) {
	# ditto
	read $fh1, $buf0, $left;
	read $fh2, $buf1, $left;
	$diff = $buf0 cmp $buf1 unless $diff;
    }
    return $diff
}

T: while (1) {
    @h0 = read_hdr $fh1, $pname0, $tarf1;
    @h1 = read_hdr $fh2, $pname1, $tarf2;
    last unless $h0[12] and $h1[12];

    while (1) {
	my $n = $h0[0] cmp $h1[0];
	if ($n == 0) {
	    my $w = hdrdiffer;
	    if ($w <= 0) { # 0 and -1: diffing not implemented yet
		consume $fh1, $h0[4];
		consume $fh2, $h1[4];
	    }
	    else {
		print "$h0[0]: file content differ\n" if compare;
	    }
	    next T
	}
	if ($n < 0) {
	    # later, collect to list to be printed at the end
	    print "$h0[0]: only in $ARGV[0]\n"; # not in argv[1]
	    consume $fh1, $h0[4];
	    @h0 = read_hdr $fh1, $pname0, $ARGV[0];
	}
	else {
	    # later, collect to list to be printed at the end
	    print "$h1[0]: only in $ARGV[1]\n"; # not in argv[0]
	    consume $fh2, $h1[4];
	    @h1 = read_hdr $fh2, $pname1, $ARGV[1];
	}
    }
    last
}

close $fh1; # or warn $!;
close $fh2; # or warn $!;
