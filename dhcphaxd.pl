#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ dhcphaxd.pl $
#
# Created: Mon 18 Nov 2013 22:25:40 EET too
# Last modified: Sun 19 Jan 2025 21:17:14 +0200 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

use 5.8.1;
use strict;
use warnings;

use IO::Socket::INET;
use Net::DHCP::Packet;
use Net::DHCP::Constants;

# fedora: perl-Net-DHCP and perl-ph
# debian: libnet-dhcp-perl

# netstat -nul
# ss -nul
# ifconfig / ip addr
# \or nmcli device modify $ ipv4.method manual ipv4.{addresses,gateway,dns} ...

$ENV{PATH} = '/sbin:/usr/sbin:/bin:/usr/bin';

my ($srvport, $peeraddr) = (67, '255.255.255.255');
while (@ARGV > 0) {
    $srvport = $ARGV[0] + 0, shift, next if $ARGV[0] =~ /^\d+$/;
    $peeraddr = $ARGV[0], shift, next if $ARGV[0] =~ /^\d+\.\d+\.\d+\.\d+/;
    last;
}
#print "$srvport $peeraddr -- @ARGV\n"; exit 0;

die "\nUsage: $0 [srv port] [peer addr] <interface> <offeredip> <r|n>

  This program replies 'offeredip' to any DHCP request arriving.
  If 'r' is given as last argument, route is set via 'interface' and
  DNS from /etc/resolv.conf (or 9.9.9.9) -- with 'n' these are not set.
  This is usable in \"point-to-point\" ethernet connection between
  2 machines e.g. for development purposes.

  Default [srv port] is 67 and default [peer addr] 255.255.255.255.\n\n"
  unless @ARGV == 3;

my $send_route;
if    ($ARGV[2] eq 'r') { $send_route = 1 }
elsif ($ARGV[2] eq 'n') { $send_route = 0 }
else { die "'$ARGV[2]' nor 'r' nor 'n'\n" }

my $lease_time = 86400 * 5; # 5 days.

##############

sub which($) {
    foreach (split /:/, $ENV{PATH}) {
	my $p = "$_/$_[0]";
	return $p if -x $p;
    }
    return '';
}

# ifconfig(8) / ip(8) is used to bring interface up.
my $ifconfig = which 'ifconfig';
unless ($ifconfig) {
    die "No 'ifconfig' nor 'ip' in \$PATH\n" unless which 'ip';
}
die "'tcpdump' not found (in \$PATH)\n" unless which 'tcpdump';


# parts from https://stackoverflow.com/questions/4101219
#	/how-can-i-find-the-ip-addresses-for-each-interface-in-perl
#use Socket;
require 'sys/ioctl.ph'; # cd /usr/include; sudo h2ph -r . (if no perl-ph or so)

# ...or use "hardcoded" values, do e.g. c code to print these out and verfy
# -- grep -r 'SIOCGIF[AN]' /usr/include may also work
# sub PF_INET () { 2 }
# sub SOCK_STREAM () { 1 }
# sub SIOCGIFADDR () { 0x8915 }
# sub SIOCGIFNETMASK () { 0x891b }

my ($localip, $localmask);

{ # -- BB --
socket(S, PF_INET, SOCK_STREAM, 0) or die "unable to create a socket: $!\n";
my $buf = pack('a256', $ARGV[0]);
my @am;
if (ioctl(S, SIOCGIFADDR(), $buf) && (@am = unpack('x20 C4', $buf))) {
    $localip = join '.', @am;
} else {
    die "Cannot resolve ipv4 address of $ARGV[0]: $!\n";
}
if (ioctl(S, SIOCGIFNETMASK(), $buf) && (@am = unpack('x20 C4', $buf))) {
    $localmask = join '.', @am;
} else {
    die "Cannot resolve ipv4 netmask of $ARGV[0]: $!\n";
}
close S;
} # -- BE --

my $offeredip = $ARGV[1];

sub quad2int($)
{
    my @bytes = split(/\./,$_[0]);
    if    (@bytes == 2) { @bytes = ( $bytes[0], "0", "0", $bytes[1] ); }
    elsif (@bytes == 3) { @bytes = ( $bytes[0], "0", $bytes[1], $bytes[2] ); }
    die "'$_[0]': bad ipv4 address format\n"
      unless @bytes == 4 && ! grep {!(/\d+$/ && $_<256)} @bytes;
    return unpack("N", pack("C4",@bytes));
}

sub int2quad($) { return join('.', unpack('C4', pack("N", $_[0]))); }

sub cidr2int($) { return 2 ** 32 - 2 ** (32 - $_[0]); }

sub w(@) { warn "WARNING: @_\n"; }

{ # -- BB --
my $ipv = quad2int $localip;
my $maskv = quad2int $localmask;
my $oipv = quad2int $offeredip;

die "'$offeredip' is the same as local ip address\n" if $ipv == $oipv;

w "'$localip' and '$offeredip' are in different networks (mask '$localmask')\n"
  unless ($ipv & $maskv) == ($oipv & $maskv);

w "'$localip' is the same as network address\n" if ($ipv == ($ipv & $maskv));
w "'$offeredip' is the same as network address\n" if ($oipv == ($oipv & $maskv));
my $im = $maskv ^ 0xffffffff;
w "'$localip' is the same as broadcast address\n" if ($ipv == ($ipv | $im));
w "'$offeredip' is the same as broadcast address\n" if ($oipv == ($oipv | $im));

} # -- BE --

##############

die "sudo!\n" unless $< == 0;

my @nameservers;
open I, '<', '/etc/resolv.conf' or die "Cannot read '/etc/resolv.conf: $!\n";
while (<I>) {
    if (/^\s*nameserver\s+(\d+)[.](\S+)/) {
	next if $1 eq '127';
	push @nameservers, "$1.$2";
    }
}
close I;
unless (@nameservers) {
    warn "Did not find name servers. Offering '9.9.9.9'.\n";
    push @nameservers, '9.9.9.9';
}

my ($chaddr, $xid, $op) = ('', '', '');
sub send_message();
sub ts();

print "netmask: $localmask, nameservers: ", join(', ', @nameservers), "\n";

while (1)
{
    # Using packet capture as it bypasses firewall -- Punching holes
    # to firewall is tedious & error prone (security risk).
    if ($ifconfig) {
	system 'ifconfig', $ARGV[0], 'up';
    } else {
	system qw/ip link set/, $ARGV[0], 'up';
    }
    open I, '-|', qw/tcpdump -i/, $ARGV[0], qw/-l -vvv -s 1500/,
      '((port 67 or port 68) and (udp[8:1] = 0x1))' or die;

    while (<I>)
    {
	#print "line: ", $_;
	# Client-Ethernet-Address 11:22:33:44:55:66 (oui Unknown)
	if    (/^\s*Client-Ethernet-Address\s+(\S+)/) {
	    $chaddr = $1;
	    $chaddr =~ tr/://d;
	}
	# xid
	elsif (/bootpc.*bootps.*DHCP.*length.*xid\s+([0-9a-fx]+)/) {
	    #    # Magic Cookie 0x63825363
	    #    elsif (/^\s*Magic Cookie\s+(\S+)/) {
	    $xid = $1;
	    $xid =~ s/^0x//;
	}
	# DHCP-Message Option 53, length 1: Discover/Request
	# DHCP-Message (53), length 1: Discover/Request
	elsif (/^\s*DHCP-Message .*\b53\b.*?(\S+)\s*$/) {
	    $op = $1;
	}
	# END Option 255, ... or like above
	elsif (/^\s*END .*\b255\b/) {
	    send_message;
	    ($chaddr, $xid, $op) = ('', '', '');
	}
    }
    print "EOF from packet filter. restarting...\n";
    sleep 1;
}
# end of "main" loop

sub send_message()
{
    print ts, "Received DHCP '$op': xid $xid, mac $chaddr\n";

    # outcommented hack that was used to fill a specific purpose...
    #if    ($chaddr eq 'aabbccddeeff') { $offeredip = "192.168.8.77"; }
    #elsif ($chaddr eq '112233445566') { $offeredip = "192.168.8.66"; }
    #else {
	#$offeredip = "192.168.8.88";
	#return;
    #}

    my ($mt, $mn);
    if    ($op eq 'Discover') {
	$mt = DHCPOFFER();
	$mn = 'offer';
    }
    elsif ($op eq 'Request') {
	$mt = DHCPACK();
	$mn = 'ack';
    }
    else {
	warn ts, "Unsupported option: '$op'. Skipping.\n";
	return;
    }

    my $S = IO::Socket::INET->new(LocalPort => $srvport,
				  LocalAddr => $localip,
				  PeerPort => 68,
				  PeerAddr => $peeraddr,
				  Proto    => 'udp',
				  Broadcast => 1)
    or die "Socket creation error: $@\n";

    my $pac = new Net::DHCP::Packet(Op => BOOTREPLY(),
				    Hops => 0,
				    Xid => hex $xid,
				    Flags => 0,
				    Ciaddr => '0.0.0.0',
				    Yiaddr => $offeredip,
				    Siaddr => $localip,
				    Giaddr => '0.0.0.0',
				    Chaddr => $chaddr,
				    DHO_DHCP_MESSAGE_TYPE() => $mt);

    $pac->addOptionValue(DHO_SUBNET_MASK(), $localmask);
    #$pac->addOptionValue(DHO_ROUTERS(), "192.168.2.1");
    $pac->addOptionValue(DHO_ROUTERS(), $localip)
      if $send_route;
    $pac->addOptionValue(DHO_DHCP_LEASE_TIME(), $lease_time);
    $pac->addOptionValue(DHO_DHCP_SERVER_IDENTIFIER, $localip);
    $pac->addOptionValue(DHO_DOMAIN_NAME_SERVERS(), "@nameservers")
      if $send_route;

    select undef, undef, undef, 0.5; # interface to become up...
    print ts, "Sending $mn. IP: $offeredip (lease_time: $lease_time seconds)\n";

    $S->send($pac->serialize()) or die "Error sending DHCP MSG #$mt: $!\n";
    undef $S;
}

sub ts()
{
    my @ts = localtime;
    return sprintf '%02d/%02d:%02d:%02d: ', $ts[3], $ts[2], $ts[1], $ts[0];
}
