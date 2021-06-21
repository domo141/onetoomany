#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
#
# $ zz -- chdir via interactive full-terminal tui $
#
# SPDX-License-Identifier: BSD-2-Clause
#
# add to .zshrc/.bashrc/...
# zz () {
#	local zz; zz=`exec /path/to/zz.pl "$PWD"`
#	test -z "$zz" || cd "$zz"
# }
#
# Author: Tomi Ollila -- too ät iki piste fi
#
# Created: Sun 08 Sep 2019 17:40:28 EEST too
# Last modified: Mon 21 Jun 2021 23:20:47 +0300 too

# lacks some features but is good enough.

use 5.8.1;
use strict;
use warnings;

use Term::ReadKey;

use locale;  # for sort collation order

$ENV{'PATH'} = '/ei-polkua-minnekään';

die "stdin not a tty\n" unless -t 0;

open OUT, ">&=", 2 or die "Cannot freopen STDERR: $!";  # for buffered output
select OUT;

require IO::Handle; # for OUT->flush() to work w/ older perls

my $cwd;
if (@ARGV) {
    $cwd = $ARGV[0];
    die "$cwd not absolute\n" unless ord($cwd) == 47;
    chdir $cwd or die "cd '$cwd': $!";
} else {
    $cwd = $ENV{PWD};
    unless (defined $cwd) {
	require POSIX; # POSIX is in smaller perl subset than Cwd
	$cwd = POSIX::getcwd();
    }
}

my ($cols, $lines, $cdline, $cdtxt, $la, $lb);

sub set_cdtxt() {
    $cdtxt = length $cwd < $cols - 4? $cwd: '...' . substr $cwd, -($cols - 8)
}

sub set_tsvars(@)
{
    my @rest;
    # # # older ReadKey.pm referenced $_[1], fixed later to ref. $_[0]
    ($cols, $lines, @rest) = @_? @_: GetTerminalSize *STDERR, *STDERR;
    die "$0: Too few columns.\n" unless $cols >= 20;
    die "$0: Too few lines.\n" unless $lines >= 11;
    $cdline = int ($lines / 2) + 1;
    $la = int ($lines / 2) - 2;
    $lb = int (($lines - 1) / 2) - 2;
    set_cdtxt;
}
set_tsvars;

$SIG{INT} = $SIG{HUP} = $SIG{TERM} = $SIG{QUIT} = sub { exit };

ReadMode 3;
print "\033[?1049h","\033[22;0;0;t"; # tput -Txterm smcup | od -a

my $endsub;
$endsub = sub {
    ReadMode 0;
    print '.',"\033[?1049l","\033[23;0;0;t"; # tput -Txterm rmcup | od -a
    undef $endsub
};
END { &$endsub if defined $endsub }

$SIG{__DIE__} = sub { &$endsub };

sub refresh();

$SIG{WINCH} = sub {
    my @newsize = GetTerminalSize *STDERR, *STDERR; # older referenced $_[1]...
    return if $newsize[0] == $cols and $newsize[1] == $lines;
    set_tsvars @newsize;
    refresh
};

# home is 1,1 (not 0,0 like w/ tput cup) (and now args reversed: col,row)
sub xcup($$) { printf "\033[%d;%dH", $_[1], $_[0] }

my (@dirs_a, @dirs_b, @dirs_af, @dirs_bf);
my $mlen = 0;
sub dirread()
{
    my @dirs;
    opendir D, '.' or die $!;
    @dirs = sort grep { -d $_ && $_ ne '.' && $_ ne '..' } readdir D;
    closedir D;
    @dirs_a = (); @dirs_b = ();
    $mlen = 0;
    my $n = int((@dirs + 1) / 2);
    my $c = 1;
    foreach (@dirs) {
	my $nlen = length;
	my $dir = $_;
	if ($nlen >= $mlen) {
	    if ($nlen >= $cols - 5) {
		$nlen = $cols - 5;
		$dir = '...' . substr $dir, -($cols - 8);
	    }
	    $mlen = $nlen;
	}
	if ($c++ > $n) { push @dirs_b, $dir } else { push @dirs_a, $dir }
    }
    @dirs_af = @dirs_a; @dirs_bf = @dirs_b;
}
dirread;

my ($pos, $col, $curcol);

sub dirline($$) {
    xcup $col, $_[0];
    print "\033[1K", $_[1], "\033[0K"; # erase left & right
}

sub refresh()
{
    my $prnt = $cdtxt; $prnt =~ s,/[^/]+$,/,;
    $col = (length $prnt) + 4;
    $col = $cols - $mlen if $col + $mlen >= $cols;
    $curcol = (length $cdtxt) + 3;
    xcup 1, $cdline; print ' ', $cdtxt, "\033[0K"; # erase right
    $pos = 0;

    my $al = @dirs_af;
    my $row = ($al < $la)? 2 + $la - $al: 2;
    xcup 1, $row; print "\033[1J"; # erase above
    foreach (@dirs_af) {
	$al--, next if $al > $la;
	dirline $row++, $_;
    }
    xcup 1, $row; print "\033[2K"; # erase line (before cdline)

    my $bl = 0;
    $row = $cdline + 1;
    xcup 1, $row++; print "\033[2K"; # erase line (after cdline)
    foreach (@dirs_bf) {
	last if $bl++ >= $lb;
	dirline $row++, $_;
    }
    print "\033[0J"; # erase below
    xcup $curcol, $cdline;
    OUT->flush();
}
refresh;

my($sel, @fl1, @fl2);

sub move($) {
    my $newpos = $pos + $_[0];
    if ($newpos < 0) {
	return if -$newpos > $la; # no scrolling (yet) so...
	my $al = @dirs_af;
	return if -$newpos > $al;
	dirline $cdline + $pos    - 1, $dirs_af[$al + $pos] if $pos != 0;
	print "\033[7m"; # inverse
	$sel = $dirs_af[$al + $newpos];
	dirline $cdline + $newpos - 1, $sel;
	print "\033[0m"; # normal
    }
    elsif ($newpos > 0) {
	return if $newpos > $lb; # ditto (note to self: scrolling regions)
	my $bl = @dirs_bf;
	return if $newpos > $bl;
	dirline $cdline + $pos    + 1, $dirs_bf[$pos-1] if $pos != 0;
	print "\033[7m"; # inverse
	$sel = $dirs_bf[$newpos-1];
	dirline $cdline + $newpos + 1, $sel;
	print "\033[0m"; # normal
    } else { # newpos == 0
	if ($pos < 0) {
	    my $al = @dirs_af;
	    dirline $cdline + $pos - 1, $dirs_af[$al + $pos];
	} else {
	    my $bl = @dirs_bf;
	    dirline $cdline + $pos + 1, $dirs_bf[$pos-1];
	}
	xcup $curcol + @fl1, $cdline;
    }
    OUT->flush();
    $pos = $newpos;
}

sub newdir($) {
    unless (chdir $_[0]) {
	xcup 2, $cdline; print "$_[0]: $!"; OUT->flush();
	ReadKey 0.2;
	xcup 1, $cdline + 1; print "\033[2K"; # erase line (after cdline)
	xcup 1, $cdline; print ' ', $cdtxt, " \033[0K"; # erase right
	OUT->flush();
	return;
    }
    $cwd = $_[0];
    @fl1 = (); @fl2 = ();
    set_cdtxt; dirread; refresh
}

my %cdirs;

sub pdir () {
    return if $cwd eq '/';
    my $prnt = $cwd; $prnt =~ s,/[^/]+$,,;
    $prnt = '/' unless $prnt;
    $cdirs{$prnt} = $cwd;
    newdir $prnt;
}

sub cdir($) {
    my $cdir;
    if ($pos == 0) {
	(print STDOUT $cwd), exit if $_[0];
	$cdir = $cdirs{$cwd};
	return unless $cdir;
    } else {
	$cdir = $cwd . '/' . $sel;
	(print STDOUT $cdir), exit if $_[0];
    }
    newdir $cdir;
}

sub dirfresh() {
    unless (@fl1) {
	@dirs_af = @dirs_a; @dirs_bf = @dirs_b; refresh;
	return 1
    }
    my $f = join '', @fl1;
    my @_af = grep { index($_, $f) >= 0 } @dirs_a;
    my @_bf = grep { index($_, $f) >= 0 } @dirs_b;
    return 0 unless @_af or @_bf;
    @dirs_af = @_af; @dirs_bf = @_bf; refresh;
    return 1
}

my $key;
while (defined ($key = ReadKey 0)) {
    if ($key eq "\033") { # ESC,
	$key = ReadKey 0.1;
	last unless defined $key; # plain ESC
	if ($key eq '[') {
	    $key = ReadKey 0;
	    last unless defined $key;
	    if    ($key eq 'A') { move -1 }
	    elsif ($key eq 'B') { move +1 }
	    elsif ($key eq 'C') { cdir 0 }
	    elsif ($key eq 'D') { pdir }
	    next # drop everything else
	}
	last if $key eq "\033"; # quick second ESC
	next # drop everything else
    }
    cdir 1 if $key eq "\n";
    if ($key eq "\177") {
	next unless @fl1;
	{ do { # see do block in perlsyn(1)
	    my $chr = ord pop @fl1;
	    last unless $chr >= 0x80 and $chr < 0xc0;
	} while (@fl1) };
	dirfresh;
	print @fl1 if @fl1;
	next
    }
    @fl2 = @fl1;
    do {
	push @fl1, $key
    } while (defined ($key = ReadKey 0.1));
    if (dirfresh) { print @fl1 }
    else { @fl1 = @fl2 }
}
