#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ ipv6llchat.pl - ipv6 link local chat $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2016 Tomi Ollila
#	    All rights reserved
#
# Created: Sun 16 Oct 2016 19:22:25 EEST too
# Last modified: Mon 03 Jun 2019 22:00:00 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

# This is "MVP" implementation of (multicast) chat using ipv6 link local
# interface. Currently sending short udp packet is supported, but no
# 'ack'ing. quite a few packets get lost, so talk to your friend nearby
# whether the message came through. A bit more chance is to get initial
# 'hello' packet through; it is sent at least twice with changing content
# so that everyone replies both messages if those arrived (following hellos
# are sent only once...). In the future (if there is any) this chat program
# should check all (these multicast) messages for a better chance to notice
# lost packets and request retransmission (when msg acks are implemented!).
# For now this is good for e.g. sending short text to be copy-pasted to
# other applications (and utilize side-channel (voice) [n]acks when needed).

my $version = '1.0';

# message protocol (currently not fully utilized):
#   [c6][m][c][time][msg]

#   c6:   16 bits  header text 'i6', 16 bits (LE)
#   m:     8 bits  message type, types described below
#   c:     8 bits  message counter -- to notice message drops
#   time: 32 bits  local time since epoch -- to notice time differences (BE)
#   msg: variable  message, as udp, packet length handled by protocol

# message types:
#   0: hello, quit. c, time, nick: version / :[quitmsg] -- link local multicast
#   1: basic message c, time, nick: message -- link local multicast
#   2: e.g.(not impl) ack msgs 0 or 1: c, time, msg=sender-ipv6 -- ll multicast
#   3: e.g.(not impl) resend request: c, time, msg=sender-ipv6 -- ll multicast
#   4: e.g.(e.g. not impl) request history from someone -- unicast
#   5: e.g.(e.g. not impl) response history -- unicast
#   6: e.g.(e.g. not impl) file transfer -- unicast
#   7: e.g.(e.g. not impl) file transfer acks -- unicast


use 5.14.0; # for IO::Socket::IP shipped part of core Socket module.
use strict;
use warnings;
use utf8;  # this program contains strings with utf-8 characters.
use Encode qw/encode_utf8 decode_utf8/;  # _utf8_on/;
use Socket qw/inet_pton pack_ipv6_mreq pack_sockaddr_in6 unpack_sockaddr_in6
	      inet_ntop PF_INET6 SOCK_DGRAM IPPROTO_UDP
	      SOL_SOCKET SO_REUSEADDR SO_BROADCAST IPPROTO_IPV6
	      IPV6_ADD_MEMBERSHIP IPV6_V6ONLY IPV6_MULTICAST_LOOP/;

# initially IO::Socket::IP was used, but during trial&error for bind() ordering
# it was changed. finally it was noticed that bind() was called at right time
# but the changed low-level stuff was left for being more detailed example
#use IO::Socket::IP;

$ENV{PATH} = '/sbin:/usr/sbin:/bin:/usr/bin';

#sub dbgm(@) { syswrite(STDOUT, "@_\n"); }

# XXX for e.g. macOS (sierra?), run `ifconfig -v` for values; just that
# "Your vendor has not defined Socket macro IPV6_ADD_MEMBERSHIP..."

sub ifaces($@)
{
    my ($_a, $_n) = @_;
    my ($num, $name, $ipv4, $iface);
    open P, '-|', qw/ip addr show/ or die;
    while(<P>) {
	($num, $name) = ($1, $2), next if /^(\d+):\s+(\S+):\s/;
	$ipv4 = $1 if /inet\s(\S+)\s/;
	next unless /inet6\s+(\S+)\s+scope link/;
	next unless defined $num;
	if ($_a eq '') {
	    substr ($name, 7) = '...' if length $name > 10;
	    printf '  %3s  %-10.10s %-30s', $num, $name, $1;
	    print " ($ipv4)" if defined $ipv4;
	    print "\n";
	}
	else {
	    die "Nick '$_n' exists as a suitable network interface.\n",
	      "Duplicate that arg on command line if so desired.\n"
	      if $num eq $_n or $name eq $_n;
	    $iface = [ $num, $name, $1, defined($ipv4)? "($ipv4)": '' ]
	      if $num eq $_a or $name eq $_a;
	}
	undef $num;
	undef $ipv4;
    }
    close P;
    return $iface if defined $iface;
    return if $_[0] eq '';
    die "Cannot find interface '$_[0]'\n";
}

sub tsmsg ($)
{
    print "Troubleshooting options:\n\n";
    print "  sudo ip6tables -I INPUT 2 -p udp --dport 7454 -j ACCEPT\n";
    print "  sudo tcpdump -X -vvne -i $_[0] port 7454\n";
    print "  ping6 -c 1 -w 1 ff02::1%$_[0]\n";
    print "  sudo ethtool -K $_[0] rx off tx off\n\n";
}

my ($iface, $nick);
if (@ARGV == 0 || @ARGV > 2)
{
    select STDERR;
    print "\nUsage: $0 [interface number or name] nick\n\n";
    print "Available interfaces:\n";
    ifaces '';
    print "\n";
    tsmsg '{iface}';
    exit;
}
elsif (@ARGV == 1)
{
    $_ = qx/ip route show to 0\/0/;
    die "Cannot find default route interface\n" unless /default.*dev\s(\S+)\s/;
    $iface = ifaces $1, $ARGV[0];
    $nick = $ARGV[0];
    die "Suspicious nick '$nick'.",
      " Choose interface manually to use such a nick.\n" if $nick =~ /^\d+$/;
}
else {
    $iface = ifaces $ARGV[0], '<no-match>';
    $nick = $ARGV[1];
}

$nick =~ s/[:\s]+$//;

tsmsg $iface->[1];
print "Welcome to use IPv6 Link Local (Multicast) Chat v$version (MVP).\n\n";
print "Commands:\n";
print "    /quit -quit /q -q  -- quit program\n";
print "    /who  -who  /w -w  -- names & addresses of other users\n";
print "\nText without command (prefix) are multicasted to the local network.";
print "\nNote: currently quite a few messages get lost in transit...";
print "\n\nUsing interface @$iface\n\n";
print 'Started ', scalar localtime, " as $nick\n";

$nick .= ':';
my $lnick = ':' . decode_utf8($nick);

my $ipv6str = $iface->[2]; $ipv6str =~ s/\/.+//;
#dbgm "$ipv6str\%$iface->[1]"; exit;

#my $sock = IO::Socket::IP->new(
#     Domain => PF_INET6,
#     V6Only => 1,
#     Type => SOCK_DGRAM,
#     #Proto => 'IPPROTO_UDP',
#     LocalHost => "$ipv6str\%$iface->[1]",
#     #LocalHost => "ffc2::1\%$iface->[1]",
#     #LocalHost => '2001:14ba:3f2:ee00:226:c7ff:fe5b:8676',
#     #Listen => 1,
#     #LocalService => 7454,
#     Blocking => 0,
#     Broadcast => 1,
#     ReuseAddr => 1) or die "Cannot create socket — $@\n";

socket(my $sock, PF_INET6, SOCK_DGRAM, IPPROTO_UDP) or die $!;

setsockopt $sock, SOL_SOCKET, SO_REUSEADDR, 1 or die $!;
#setsockopt $sock, SOL_SOCKET, SO_BROADCAST, 1 or die $!;
setsockopt $sock, IPPROTO_IPV6, IPV6_V6ONLY, 1 or die $!;
#setsockopt $sock, IPPROTO_IPV6, IPV6_MULTICAST_LOOP, 1 or die $!;
# The above did not help on Fedora 23 or 24 (on 20 and ubuntu 16.04 it did)
# receiving and showing own packets would have helped (a bit) to notice
# when own packets are not (also) leaving the machine...
# (to me it looked like ip6_finish_output2() does it but which ifs...)
setsockopt $sock, IPPROTO_IPV6, IPV6_MULTICAST_LOOP, 0 or die $!;

#bind($sock, pack_sockaddr_in6(7454, inet_pton(PF_INET6, $ipv6), $iface->[0]))
#  or die $!;
# so, bind to :: (IN6ADDR_ANY) and we can receive !
bind($sock, pack_sockaddr_in6(7454, inet_pton(PF_INET6, "::"), $iface->[0]))
  or die $!;

#my $my_ip6 = getsockname $sock;
#(undef, $my_ip6) = unpack_sockaddr_in6($my_ip6);
#print inet_ntop(PF_INET6, $my_ip6), "\n";

# the above gives "::"; hopefully using $ipv6str is robust enough (XXX)

#my $my_ip6 = inet_pton(PF_INET6, $ipv6str);

my $mcast_group = 'ff02:1dea:aa7e:a51a:00d1:c0de:c001:d157';
{
my $ipv6_mreq = pack_ipv6_mreq(inet_pton(PF_INET6, $mcast_group), $iface->[0]);
setsockopt $sock, IPPROTO_IPV6, IPV6_ADD_MEMBERSHIP, $ipv6_mreq or die $!;
}

#printf "%d\n", unpack "I", getsockopt($sock,IPPROTO_IPV6,IPV6_MULTICAST_LOOP);

#exec '/bin/true'; # for strace(1)

my $mcaddr
#  = sockaddr_in6( 7454, inet_pton(PF_INET6, 'ff02::1%wlp3s0') );
#  = sockaddr_in6( 7454, inet_pton(PF_INET6, 'ff02::1', 'wlp3s0') );
#  = sockaddr_in6( 7454, inet_pton(PF_INET6, 'ff02::1234', 'wlp3s0') );
  = pack_sockaddr_in6(7454, inet_pton(PF_INET6, $mcast_group), $iface->[0]);

my $mmcntr = 0;
my $resend_helo;
my $stm = 0;
sub sendhelo($)
{
    # add quit-msg with ':' (a'la IRC multi-word messages) (tbd)
    my $msg = encode_utf8($_[0]);
    $msg = pack 'A2CCN A* A A*', 'i6', 0, $mmcntr, $stm, $nick, ' ', $msg;
    send $sock, $msg, 0, $mcaddr;
    $resend_helo = 0;
    $stm = time unless $stm;  # increase chance by getting 2 replies initially
    #print '<R>';
}
sendhelo $version;
$resend_helo = 1;
my $outpfx = "\r";

sub sendexit($) { sendhelo ':' . $_[0]; exit }

sub sendmmsg($)
{
    $mmcntr++;
    my $msg = encode_utf8($_[0]);
    $msg = pack 'A2CCN A* A A*', 'i6', 1, $mmcntr, time, $nick, ' ', $msg;
    send $sock, $msg, 0, $mcaddr;
}

# some of this code below was first started Sat Oct 12 17:23:35 1996 too

my $rin = '';
my $fin = fileno(STDIN);
my $fs = fileno($sock);

vec($rin, $fin, 1) = 1;
vec($rin, $fs, 1) = 1;

sub sread();
sub iread();
sub cmdline();

my @inchrs;
my @weekday = qw/Sun Mon Tue Wed Thu Fri Sat Sun/;
my $prevday = 0;

sub reset () { print "\r\nexit\r\n"; system qw/stty sane/; exit }

# note to self: rlwrap(1) # but, how to handle incoming msgs while writing ?
my ($rows, $cols);
sub get_size () { my $s = qx/stty size/;
		  $s =~ /(\d+)\s+(\d+)/; ($rows, $cols) = ($1, $2) }
get_size;

eval 'END { &reset; }';
$SIG{TERM} = $SIG{INT} = \&reset;
$SIG{WINCH} = sub { get_size };
system qw/stty raw -echo/;
select((select(STDOUT), $| = 1)[$[]);
binmode STDIN, ':utf8';
binmode STDOUT, ':utf8';

while (1)
{
    my ($x, $rout);

    if ($outpfx eq '') {
	$x = select $rout = $rin, undef, undef, undef;
    }
    else {
	$x = select $rout = $rin, undef, undef, 1.0;
    }
    #dbgm $x;
    if ($x > 0) {
	sread if vec($rout, $fs, 1);
	iread if vec($rout, $fin, 1);
    }
    elsif ($x == 0) {
	cmdline;
    }
    else {
	# if select() starts failing...
	select undef, undef, undef, 0.25;
    }
}

sub dispdate()
{
    my @lt = localtime;
    if ($prevday != $lt[3]) {
	if ($prevday) {
	    printf "Day changed to %s %d-%02d-%02d\r\n", $weekday[$lt[6]],
	      $lt[5] + 1900, $lt[4] + 1, $lt[3];
	}
	$prevday = $lt[3];
    }
    printf '%02d/%02d:%02d', $lt[3], $lt[2], $lt[1];
}

sub display(@)
{
    dispdate;
    print ' ', @_, "\r\n";
}

sub beforestdout()
{
    if ($outpfx eq '') {
	if (@inchrs) {
	    my $clen = @inchrs >= $cols? $cols - 1: @inchrs;
	    print "\r", ' ' x $clen, "\r";
	}
    }
    else {
	print $outpfx;
    }
}

my %names;
sub handle_names($$$$)
{
    my ($mc, $ts, $ip6, $msg) = @_;
    my ($nick, $version) = split ':\s+', $msg, 2;
    $nick = decode_utf8 $nick;
    my $nref = $names{$ip6};

    if ($version =~ s/^://) {
	beforestdout;
	display "Exit: $nick (", ($version? $version: '!'), ')';
	delete $names{$ip6} if defined $nref;
	$outpfx = "\r";
	return;
    }
    # for future expansion, there might be e.g. address list of other users
    # after version, to ensure better change of seeing them all...
    $version =~ s/\0.*//; # ... so that such change does not break this client

    return if defined $nref and $nref->[1] eq $ts
      and $nref->[2] eq $nick and $nref->[3] eq $version;
    $names{$ip6} = [ $mc, $ts, $nick, $version ];
    $resend_helo = 1;
    $outpfx = "\r", return if defined $nref; # XXX "silent" quit and rejoin...
    if ($outpfx ne "\r\n") {
	beforestdout, dispdate, print " Seen: $nick";
	$outpfx = "\r\n";
    }
    else { print ' · ', $nick; }
}

sub sread()
{
    my $msg;
    my $addr = recv $sock, $msg, 2048, 0;
    unless (defined $addr) {
	return if $! =~ /^Interrupted/;
	die "r\nSocket recv error: $!r\n";
    }
    return unless length $msg > 9;
    my $ip6 = unpack_sockaddr_in6 $addr;
    #return if $ip6 eq $my_ip6;
    #display inet_ntop(PF_INET6, $ip6);

    my ($id, $mt, $mc, $ts) = unpack 'A2CCN', $msg;
    return unless $id eq 'i6';
    $msg = substr $msg, 8;
    handle_names($mc, $ts, $ip6, $msg), return if $mt == 0;
    return unless $mt == '1';
    $msg =~ tr/\000-\037//d;
    beforestdout;
    display ':', decode_utf8($msg);
    $outpfx = "\r";
}

sub cmd_who($);

sub iread()
{
    cmdline if $outpfx ne '';

    my $ibuf;
    my $len = sysread(STDIN, $ibuf, 1024);

    unless (defined $len) {
	return if $! =~ /^Interrupted/;
	die "r\nStdin read error: $!r\n";
    }
    exit if $len == 0;

    foreach ( split //, $ibuf )
    {
	if ($_ eq "\003") {
	    @inchrs = ();
	    print "\r   +++ Clearing line +++   \r\n";
	}
	elsif ($_ eq "\177" || $_ eq "\010")
	{
	    if (@inchrs) {
		pop(@inchrs);
		print "\b \b";
	    }
	}
	elsif ($_ ne "\n" && $_ ne "\r") {
	    next if ord $_ < 0x20;
	    push (@inchrs, $_);
	    print $_;
	}
	else {
	    return unless @inchrs;
	    beforestdout;
	    $_ = join('', @inchrs);
	    @inchrs = ();
	    if (s/^[-\/]// and not s/^\s//) {
		sendexit $_ if s/^q\b\s*// or s/^quit\b\s*//;
		cmd_who($_), return if (s/^w\b\s*// or s/^who\b\s*//);
		display '¡', $_, '! -- unknown command';
		return;
	    }
	    $outpfx = '';
	    # if IPV6_MULTICAST_LOOP worked everywhere...
	    display $lnick,' ',$_; # ...this line could have been outcommented.
	    sendmmsg $_;
	}
    }
}

sub cmdline()
{
    sendhelo $version if $resend_helo;
    print $outpfx;
    $outpfx = '';
    print join('', @inchrs) if (@inchrs);
}

sub cmd_who($)
{
    beforestdout;
    while (my ($key, $value) = each %names) {
	printf "  %-25s  %-4.4s  %s\r\n", inet_ntop(PF_INET6, $key),
	  $value->[3], $value->[2];
    }
    printf "  %-25s  %-4.4s  %s <- me\r\n", $ipv6str, $version, $lnick;
    $outpfx = '';
}
