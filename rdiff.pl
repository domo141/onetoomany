#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ rdiff.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2021 Tomi Ollila
#	    All rights reserved
#
# Created: Mon 14 Jun 2021 22:11:24 EEST too
# Last modified: Mon 21 Jun 2021 23:38:35 +0300 too

use 5.8.1;
use strict;
use warnings;
use Socket;

# hint: when testing, execute ./rdiff.pl . diff ./rdiff.pl

sub _die (@) { print STDERR "@_\n"; exit 1 }

my $bn0;
BEGIN {
    $bn0 = $0; $bn0 =~ s,.*/,,;
    #_die "Usage: $bn0 [options] file1 file2 [file3]\n",
    _die "Usage: $bn0 [options] file1 file2\n",
      "  (1. $bn0 . 'diff-cmdline' tunnel-cmdline)" if @ARGV < 2;
}

# Q. Why is this so clumsy?
# A. The trick is to use Perl's strengths rather than its weaknesses.

# I.e. iterate until it works! That's fun!

my $c;
sub xread_to__(*$;$)
{
    my $fh = shift;
    my $l = read $fh, $_, $_[0], $_[1] // 0;
    _die "$c: read failure: $!" unless defined $l;
    _die "$c: short read: expected $_[0], got $l bytes" unless $l == $_[0];
}

my $sockpath;

BEGIN {
    $| = 1;
    select STDERR;

    # note: abstract socket namespace (linux only ?)
    # no need to play w/ potentially dangling socket file
    $sockpath = "\0@/tmp/rdiff-1-$<";

    sub readfile($$)
    {
	my $fn = $_[0] eq '-' ? '/dev/stdin' : $_[0];
	open I, '<', $fn or _die "Cannot open '$fn': $!";
	my $l = read I, $_[1], 1e6; # reads until eof from file, pipe...
	close I;
	_die "'$ARGV[0]': read failed: $!" unless defined $l;
	_die "'$ARGV[0]': file too large (>= 1MB)" if $l == 1e6;
	$l
    }

    sub writefile($$)
    {
	xread_to__ \*S, $_[1];
	my $of = "$_[0]-new";
	print "writing '$of', $_[1] bytes\n";
	open O, '>', $of or _die "Opening for write failed: $!";
	print O $_ or _die "Write failed: $!";
	close O or _die "Write failed: $!";
    }

    if ($ARGV[0] ne '.')
    {
	my @opts;
	while (@ARGV && $ARGV[0] =~ /^-(.)(.*)/) {
	    my $arg = shift;
	    last if $arg eq '--';
	    if ($1 ne '-') {
		my ($i, $z) = ($1, $2);
		W: while (1) {
		      foreach (qw/w b i B a/) { next W if $i eq $_ }
		      _die "'-$i': unknown option";
		  } continue {
		      $z =~ /(.)(.*)/ or last;
		      ($i, $z) = ($1, $2);
		  }
		  push @opts, $arg;
		  next
	      }
	    my $m = 0;
	    foreach (qw/--ignore-all-space --ignore-space-change --ignore-case
			--ignore-blank-lines --text/)
	    {
		push(@opts, $arg), $m = 1, last if $_ eq $arg
	    }
	    _die "'$arg': unknown option" unless $m;
	}
	_die "$bn0: too many args (2 file args)" unless @ARGV == 2;

	# note: '-' '-' allowed as args, first gets all data second none
	_die "'$ARGV[0]' not readable" unless $ARGV[0] eq '-' or -r $ARGV[0];
	_die "'$ARGV[1]' not readable" unless $ARGV[1] eq '-' or -r $ARGV[1];

	$c = 'd'; # for xread_to_()
	socket S, PF_UNIX, SOCK_STREAM, 0, or _die "socket: $!";
	my $addr = pack_sockaddr_un($sockpath);
	connect S, $addr or _die "Cannot connect to $bn0 socket $sockpath: $!";
	select((select(S), $| = 1)[$[]);

	my $fdata1; my $l1 = readfile $ARGV[0], $fdata1;
	my $fdata2; my $l2 = readfile $ARGV[1], $fdata2;

	my $opts = "@opts";
	my $pack = pack 'LLLLLLL',
	  length($opts), length($ARGV[0]), length($ARGV[1]), 0, $l1, $l2, 0;

	print S $pack, $opts, $ARGV[0], $ARGV[1], $fdata1, $fdata2
	  or die "print failed: $!"; # die for line numbers
	($fdata1, $fdata2) = ('', '');
	xread_to__ \*S, 12;
	($l1, $l2) = unpack 'LL'; # 3rd missing fttb
	#warn "$l1, $l2";
	writefile $ARGV[0], $l1 if $l1;
	writefile $ARGV[1], $l2 if $l2;
	#sleep 100; # for strace
	exit
    }
}

my $ident = "rdiff-1\0\n";

my ($o0, $n1, $n2, $n3, $l1, $l2, $l3);

sub read_pipedS()
{
    xread_to__ \*S, 28;
    ($o0, $n1, $n2, $n3, $l1, $l2, $l3) = unpack 'LLLLLLL', $_;
    #warn "$c: $o0, $n1, $n2, $n3, $l1, $l2, $l3";
    my $len = $o0 + $n1 + $n2 + $n3 + $l1 + $l2 + $l3;
    #warn "$c: $len";
    xread_to__ \*S, $len, 28;
}

if ($ARGV[1] eq 'l:sten') {
    $c = 's';
    #socket SS, PF_UNIX, SOCK_SEQPACKET, 0, or _die "socket: $!";
    socket SS, PF_UNIX, SOCK_STREAM, 0, or _die "socket: $!";
    my $addr = pack_sockaddr_un($sockpath);
    bind SS, $addr or _die "Cannot bind $sockpath: $!";
    listen SS, 5;
    syswrite STDOUT, $ident;
    print "s: waiting 'rdiff-1' response from c\n";
    sysread STDIN, $_, 32;
    _die "s: did not get rdiff-1...from c" unless $_ eq $ident;
    print "s: response ok -- ready to receive diff content from $bn0\n";
    my ($cin, $sin) = (0, fileno(SS));
    my $in = ''; vec($in, $cin, 1) = 1; vec($in, $sin, 1) = 1;
    while (1) {
	my $out; select($out = $in, undef, undef, undef);
	if (vec($out, $sin, 1)) {
	    if (accept(S, SS)) {
		print "s: accepted -- to be forwarded to c...\n";
		select((select(S), $| = 1)[$[]);
		read_pipedS;
		#warn "s: rlen: ", length, " writing to c...";
		print STDOUT $_ or die "print failed: $!"; # die for line num..
		xread_to__ \*STDIN, 12;
		($l1, $l2) = unpack 'LL';
		my $len = $l1 + $l2;
		xread_to__ \*STDIN, $len, 12 if $len;
		#warn "s: transfer ", length, " bytes";
		print S $_ or die "print failed: $!"; # die for line numbers
		close S;
	    }
	    else {
		_die "s: accept() failed unexpectedly: $!" unless $!{EINTR}
	    }
	}
	if (vec($out, $cin, 1)) {
	    _die "s: sysread: $!" unless defined sysread STDIN, $_, 4096;
	    _die "s: EOF from c" unless $_;
	    warn "s: ignoring unexpected message from c\n";
	}
    }
    # not reached #
}

# kilentti

_die "No tunnel cmdline!" unless @ARGV > 2;

my @diffc = split ' ', $ARGV[1];
splice @ARGV, 0, 2;
socketpair S, C, PF_UNIX, SOCK_STREAM, 0 or _die "socketpair: $!";
if (fork == 0) {
    # child
    close S;
    open STDIN, '<&', \*C or _die "Redirecting stdin: $!";
    open STDOUT, '>&', \*C or _die "Redirecting stdout: $!";
    $ENV{LC_ALL} = $ENV{LANG} = 'C';
    print "c: executing @ARGV ...\n";
    exec @ARGV, '.', 'l:sten';
    die "Executing @ARGV failed: $!"
}
# parent
close C;
$c = 'c';
select((select(S), $| = 1)[$[]);
syswrite S, $ident;
print "c: waiting 'rdiff-1' response from s\n";
sysread S, $_, 32;
_die "c: did not get rdiff-1... from s" unless $_ eq $ident;
print "c: response ok -- ready to receive diff content from s\n";

my $tdir = $ENV{XDG_RUNTIME_DIR} || "/tmp"; # /tmp if undefined or empty
$tdir = "$tdir/rdiff-$<-$$";
mkdir $tdir, 0700 or _die "Cannot mkdir $tdir: $!";
eval 'END { system qw/rm -rf/, $tdir if defined $tdir }';
$SIG{HUP} = $SIG{INT} = $SIG{QUIT} = $SIG{TERM} = sub { print "\n"; exit };

chdir $tdir or _die "Cannot chdir to $tdir: $!";

sub tfn($$)
{
    my $b = $_[0]; $b =~ s|.*/||;
    #$b = tr/+-9=@-Z_a-z/./c;
    return "$_[1],$b";
}

sub sendfile($$)
{
    open I, '<', $_[0];
    xread_to__ \*I, $_[1];
    close I;
    #warn "c: sending '$_[0]' -- $_[1] bytes";
    print S $_ or die "print failed: $!"; # die for line numbers
}

sub writefile2($$) # 2nd impl...
{
    open O, '>', $_[0] or _die "Cannot open $_[0] for writing: $!";
    print O $_[1] or _die "Writing to $_[0] failed: $!";
    close O or _die "Writing to $_[0] failed: $!";
}

while (1) {
    read_pipedS;
    my ($o, $n); $n = 28;
    $o = $n; $n = $o + $o0; my $opts = substr $_, $o, $n - $o;
    $o = $n; $n = $o + $n1; my $fname1 = substr $_, $o, $n - $o;
    $o = $n; $n = $o + $n2; my $fname2 = substr $_, $o, $n - $o;
    $o = $n; $n = $o + $n3; my $fname3 = substr $_, $o, $n - $o;
    #warn "c: '$fname1', '$fname2', '$fname3'";
    $o = $n; $n = $o + $l1; my $fdata1 = substr $_, $o, $n - $o;
    $o = $n; $n = $o + $l2; my $fdata2 = substr $_, $o, $n - $o;
    $o = $n; $n = $o + $l3; my $fdata3 = substr $_, $o, $n - $o;
    $_ = '';
    print "c: $fname1 ($l1) : $fname2 ($l2)\n";
    my $afn = tfn $fname1, 'a'; writefile2 $afn, $fdata1; my @s1 = stat $afn;
    my $bfn = tfn $fname2, 'b'; writefile2 $bfn, $fdata2; my @s2 = stat $bfn;
    #warn "c: %d %d %d\n", length($ft1), length($ft2), length($ft3);
    my @opts = split ' ', $opts;
    system @diffc, @opts, $afn, $bfn;
    #system qw/ls -l/;
    my @se1 = stat $afn; my $al = ("@se1[7,9]" eq "@s1[7,9]")? 0: $se1[7];
    my @se2 = stat $bfn; my $bl = ("@se2[7,9]" eq "@s2[7,9]")? 0: $se2[7];
    #warn "c: /// $al -- $bl ///";
    #warn "c: @se2\n@s2\n -";
    print S pack 'LLL', $al, $bl, 0 or die "print failed: $!"; # die for line n
    sendfile $afn, $al if $al;
    sendfile $bfn, $bl if $bl;
    unlink $afn, $bfn;
}
