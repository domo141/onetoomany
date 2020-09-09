#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ custar.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2020 Tomi Ollila
#	    All rights reserved
#
# Created: Fri 21 Aug 2020 18:18:04 EEST too
# Last modified: Thu 10 Sep 2020 01:05:59 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

# v0.9: device nodes, fifos ignored. (usage) docs to be updated.

use 5.012;  # so readdir assigns to $_ in a lone while test
use strict;
use warnings;

use POSIX qw/mktime getcwd/;

$ENV{TZ} = 'UTC';

die "Usage: $0 tarname mtime [options] [--] dirs/files\n" unless @ARGV > 2;

my $of = shift;

my %zc = ( '.tar' => '', '.tar.bzip2' => 'bzip2',
	   '.tar.gz' => 'gzip --no-name', '.tgz' => 'gzip --no-name',
	   '.tar.xz' => 'xz', '.txz' => 'xz',
	   '.tar.lz' => 'lzip', '.tlz' => 'lzip' );

$of =~ /\S((?:[.]tar)?[.]?[.]\w+)$/;

my $zc;

die "Unknown format in '$of': not in (fn" . join(', fn', sort keys %zc) . ")\n"
  unless defined $1 and defined ($zc = $zc{$1});

my $gmtime = shift;

if ($gmtime eq '-') {
    $gmtime = time;
} elsif ($gmtime =~ /^\d$/) {
    $gmtime = time - 86400 * $gmtime;
    $gmtime = $gmtime - $gmtime % 86400;
} elsif ($gmtime =~
	 /(20\d\d)-([01]\d)-([0-3]\d)/) {
    $gmtime = mktime(0, 0, 0, $3, $2 - 1, $1 - 1900);
} elsif ($gmtime =~
	 /(20\d\d)-([01]\d)-([0-3]\d)\+([012]\d)/) {
    $gmtime = mktime(0, 0, $4, $3, $2 - 1, $1 - 1900);
} elsif ($gmtime =~
	 /(20\d\d)-([01]\d)-([0-3]\d)\+([012]\d):([0-5]\d)/) {
    $gmtime = mktime(0, $5, $4, $3, $2 - 1, $1 - 1900);
} elsif ($gmtime =~
	 /(20\d\d)-([01]\d)-([0-3]\d)[+T]([012]\d):([0-5]\d):(\[0-5]\d)/) {
    $gmtime = mktime($6, $5, $4, $3, $2 - 1, $1 - 1900);
}
else { die "'$gmtime': unknown time format\n"; }

my @excludes;
my @xforms;
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
	push @xforms, $1;
	next
    }
    if ($_ eq '--xform' || $_ eq '--transform') {
	die "No value for '$_'\n" unless @ARGV;
	push @xforms, shift;
	next
    }
    if ($_ =~ /^--xform=(.*)/ || $_ =~ /^--transform=(.*)/) {
	push @xforms, $1;
	next
    }
}

my $swd;
if (defined $tcwd) {
    # note: dirhandles, play with first to get understanding...
    die "'$tcwd': not a directory\n" unless -d $tcwd;
    $swd = getcwd;
    #... alternative, openat(2)...
}
foreach (@excludes) {
    # good enough? glob-to-re conversion ?
    $_ = "^$_" unless s/^[*]+//;
    $_ = "$_\$" unless s/[*]+$//;
    s/[.]/[.]/g; s/[*]/.*/g; s/[?]/./g;
    $_ = qr/$_/;
}
sub xforms($);
if (@xforms) {
    my $eval = 'sub xforms($) {';
    #
    # Current solution is to "eval" replace script run time. Due to input
    # restrictions full perl regexp substitution interface is not available
    # (';'s dropped, separator after initial 's' must be non-word character).
    # Improvements welcome.
    #
    foreach (@xforms) {
	# early checks...
	die "'$_' does not start with 's'\n" unless /^s\W/;
	tr/;//d;
	my $p = substr($_, 1, 1);
	my $s = substr($_, -1, 1);
	die "'$_' not s$p...$p...$p nor s$s...$s...$s\n" unless $p eq $s;
	$eval .= "\n \$_[0] =~ $_;";
    }
    $eval .= "\n}; 1";
    eval $eval or die "Unsupported/broken --xform/--transform content\n";
}

die "No files/dirs\n" unless @ARGV;

my @filelist;

sub add_filentry($$) {
    my $ftn = $_[1];
    xforms $ftn if @xforms;
    # no exclude/include/xform (yet), so all unless size)
    die "name len of '$ftn' is too long\n" if length($ftn) > 99;
    my @st = lstat $_[1];
    if (-l _) {
	my $sl = readlink $_[1]; # fixme: check error (and test it)
	die "symlink len of '$sl' is too long\n" if length($sl) > 99;
    }
    push @{$_[0]},
      # name    dev     ino     mode    nlink   rdev    size
      [ $_[1], $st[0], $st[1], $st[2], $st[3], $st[6], $st[7], $ftn ]
}

sub add_dir($$);
sub add_dir($$) {
    my $d = $_[1]; # $_[1] is reference (alias actually), copy ($_[0] fine)
    add_filentry $_[0], $d.'/' unless $d eq '.';
    opendir my $dh, $d or die $!;
    $d = ($d eq '.')? '': "$d/";
    L: while (readdir $dh) {
	next if $_ eq '.' or $_ eq '..';
	foreach my $re (@excludes) {
	    next L if $_ =~ $re;
	}
	my $de = "$d$_";
	lstat $de;
	if (! -l _ and -d _) {
	    add_dir $_[0], $de;
	    next
	}
	if (-e _) {
	    add_filentry $_[0], $de;
	    next
	}
	warn "internal problem: '$de' not found\n"
    }
    closedir $dh; # does this make any difference
}

if (defined $tcwd) {
    chdir $tcwd or die "Cannot chdir to '$tcwd'. $!\n"
}

for (@ARGV) {
    my $files = [ ];
    push @filelist, $files;
    lstat;
    if (! -l _ and -d _) {
	s:/+$::;
	add_dir $files, $_;
	next
    }
    if (-e _) {
	add_filentry $files, $_;
	next
    }
    die "'$_': no such file or directory\n";
}

if (defined $swd) {
    chdir $swd or die "Cannot chdir to '$swd': $!\n"
}

# declare tarlisted.pm functions #

sub _tarlisted_mkhdr($$$$$$$$$$);
sub _tarlisted_writehdr($);
sub _tarlisted_xsyswrite($);
sub _tarlisted_addpad();
my $_tarlisted_wb = 0;

sub tarlisted_open($@); # name following optional compression program & args
sub tarlisted_close();

my $owip;
END { return unless defined $owip; chdir $swd if defined $swd; unlink $owip }

$owip = "$of.wip";
tarlisted_open $owip, (split " ", $zc);

if (defined $tcwd) {
    chdir $tcwd or die "Cannot chdir to '$tcwd'. $!\n"
}

#use Data::Dumper;

my $dotcount = 0;
my %links;
foreach (@filelist) {
    # note: C locale, only tr/A-Z/a-z/ is done
    my @list = sort { lc $a->[7] cmp lc $b->[7] } @{$_};
    #my $dotcount = 0;
    foreach (@list) {
	#print Dumper($_);
	my $prm = $_->[3] & 0777;
	#print $_->[0], " ", $->[7], " ", $prm, "\n";
	print(((++$dotcount) % 72)? '.': "\n");
	lstat $_->[0];
	if (! -l _ and -d _) {
	    _tarlisted_writehdr _tarlisted_mkhdr
	      $_->[7], $prm, 0,0, 0, $gmtime, '5', '', 'root','root';
	    next
	}
	next unless -f _ or -l _;
	# fixme: device nodes, fifos not yet handled (refactor this foreach...)
	my ($name, $size) = ($_->[0], $_->[6]);
	my ($type, $lname) = ('0', '');
	if (-l _) {
	    $type = '2';
	    $lname = readlink $_->[0];
	    $size = 0;
	    $prm = oct(777);
	}
	elsif ($_->[4] > 1) {
	    my $devino = "$->[1].$->[2]";
	    $lname = $links{$devino};
	    if (defined $lname) {
		$type = '1';
		$size = 0;
	    }
	    else {
		$lname = '';
		$links{$devino} = $_->[7];
	    }
	}
	_tarlisted_writehdr _tarlisted_mkhdr
	  $_->[7], $prm, 0,0, $size, $gmtime, $type, $lname, 'root','root';

	next if $lname;

	open my $in, '<', $name or die "opening '$name': $!\n";
	my $buf; my $tlen = 0;
	while ( (my $len = sysread($in, $buf, 65536)) > 0) {
	    _tarlisted_xsyswrite $buf;
	    $tlen += $len;
	}
	die "Short read ($tlen != $size)!\n" if $tlen != $size;
	close $in; # fixme, check
	$_tarlisted_wb += $tlen;
	_tarlisted_addpad;
    }
    #print "\n" if $dotcount % 72;
}
print "\n" if $dotcount % 72;

if (defined $swd) {
    chdir $swd or die "Cannot chdir to '$swd': $!\n"
}

tarlisted_close and die "Closing tar file failed: $!\n";

rename $owip, $of;
undef $owip;

# from tarlisted.pm #

my $_tarlisted_pid;

sub _tarlisted_pipetocmd(@)
{
    pipe PR, PW;
    $_tarlisted_pid = fork;
    die "fork() failed: $!\n" unless defined $_tarlisted_pid;
    unless ($_tarlisted_pid) {
	# child
	close PW;
	open STDOUT, '>&TARLISTED';
	open STDIN, '>&PR';
	close PR;
	close TARLISTED;
	exec @_;
	die "exec() failed: $!";
    }
    # parent
    close PR;
    open TARLISTED, '>&PW';
    close PW;
}


# IEEE Std 1003.1-1988 (“POSIX.1”) ustar format
# name perm uid gid size mtime type lname uname gname
sub _tarlisted_mkhdr($$$$$$$$$$)
{
    if (length($_[7]) > 99) {
	die "Link name '$_[7]' too long\n";
    }
    my $name = $_[0];
    my $prefix;
    if (length($name) > 99) {
	die "Name splitting not implemented ('$name' too long)\n";
    }
    else {
	$name = pack('a100', $name);
	$prefix = pack('a155', '');
    }
    my $mode = sprintf("%07o\0", $_[1]);
    my $uid = sprintf("%07o\0", $_[2]);
    my $gid = sprintf("%07o\0", $_[3]);
    my $size = sprintf("%011o\0", $_[4]);
    my $mtime = sprintf("%011o\0", $_[5]);
    my $checksum = '        ';
    my $typeflag = $_[6];
    my $linkname = pack('a100', $_[7]);
    my $magic = "ustar\0";
    my $version = '00';
    my $uname = pack('a32', $_[8]);
    my $gname = pack('a32', $_[9]);
    my $devmajor = "0000000\0";
    my $devminor = "0000000\0";
    my $pad = pack('a12', '');

    my $hdr = join '', $name, $mode, $uid, $gid, $size, $mtime,
      $checksum, $typeflag, $linkname, $magic, $version, $uname, $gname,
	$devmajor, $devminor, $prefix, $pad;

    my $sum = 0;
    foreach (split //, $hdr) {
	$sum = $sum + ord $_;
    }
    $checksum = sprintf "%06o\0 ", $sum;
    $hdr = join '', $name, $mode, $uid, $gid, $size, $mtime,
      $checksum, $typeflag, $linkname, $magic, $version, $uname, $gname,
	$devmajor, $devminor, $prefix, $pad;

    return $hdr;
}


sub _tarlisted_xsyswrite($)
{
    my $len = syswrite TARLISTED, $_[0] or 0;
    my $l = length $_[0];
    while ($len < $l) {
	die "Short write!\n" if $len <= 0;
	my $nl = syswrite TARLISTED, $_[0], $l - $len, $len or 0;
	die "Short write!\n" if $nl <= 0;
	$len += $nl;
    }
}

#my $_tarlisted_wb = 0;


sub _tarlisted_writehdr($)
{
    _tarlisted_xsyswrite $_[0];
    $_tarlisted_wb += 512;
}


sub _tarlisted_addpad()
{
    if ($_tarlisted_wb % 512 != 0) {
	my $more = 512 - $_tarlisted_wb % 512;
	_tarlisted_xsyswrite "\0" x $more;
	$_tarlisted_wb += $more;
    }
}


sub tarlisted_open($@)
{
    die "tarlisted alreadly open\n" if defined $_tarlisted_pid;
    $_tarlisted_pid = 0;
    if ($_[0] eq '-') {
	open TARLISTED, '>&STDOUT' or die "dup stdout: $!\n";
	return;
    }
    open TARLISTED, '>', $_[0] or die "> $_[0]: $!\n";
    shift;
    _tarlisted_pipetocmd @_ if @_;
    $_tarlisted_wb = 0;
}


sub tarlisted_close()
{
    # end archive
    _tarlisted_xsyswrite "\0" x 1024;
    $_tarlisted_wb += 1024;

    if ($_tarlisted_wb % 10240 != 0) {
	my $more = 10240 - $_tarlisted_wb % 10240;
	_tarlisted_xsyswrite "\0" x $more;
	$_tarlisted_wb += $more;
    }
    close TARLISTED; # fixme: need check here.
    $? = 0;
    waitpid $_tarlisted_pid, 0 if $_tarlisted_pid;
    undef $_tarlisted_pid;
    return $?;
}
