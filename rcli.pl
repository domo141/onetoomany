#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ rcli.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2024 Tomi Ollila
#	    All rights reserved
#
# Created: Sun 26 May 2024 12:49:11 EEST too
# Last modified: Tue 18 Jun 2024 22:24:40 +0300 too

### code-too-remote ###
use 5.8.1;
use strict;
use warnings;
use POSIX;

my $rorl;
sub pdie (@) {
    die "$rorl: $!\n" unless @_;
    die "$rorl: @_ $!\n" if $_[$#_] =~ /:$/;
    die "$rorl: @_\n"
}
my $synmsg;
### end ###
$rorl = 'local';

# Tries to load (likely) 'Gnu' if exists, then 'Perl', fallbacks to 'Stub'
# Try : env PERL_RL=Perl rcli.pl ... to try with 'Perl' when 'Gnu' is available
# Hmm. Zoid may (not) be recognized ... PERL_RL=Zoid ... to the rescue...
# also, for local testing: ./rcli.pl perl - -
use Term::ReadLine;

# the idea with leading '.' is that "perl" is kinda hidden from command line

$0 =~ s:.*/::, die "\nUsage: $0 [.] remote-cmdline [[path/to/]perl]

When first arg is '.', 'perl' if appended to the args (so you don't have to)

Like: $0 . ssh user\@host  (execute  $0 perl - -  ;: to try locally)\n
" if @ARGV < 3;

shift, push @ARGV, 'perl' if $ARGV[0] eq '.';

my $term = Term::ReadLine->new('remote cli in perl');

#use Data::Dumper; print Dumper($term->Attribs); exit 0;

my $pnl = "\n";
aB: {
    my $rli = Term::ReadLine->ReadLine;
    print "Readline package: $rli\n";
    sub _rl_complete;
    if ($rli eq 'Term::ReadLine::Gnu') {
	$term->Attribs->{completion_function} = \&_rl_complete;
	last
    }
    if ($rli eq 'Term::ReadLine::Perl' or $rli eq 'Term::ReadLine::Zoid') {
	no warnings;
	$readline::rl_completion_function = \&_rl_complete;
	$pnl = '';
	last
    }
    if ($rli eq 'Term::ReadLine::Stub') {
	print STDERR "\nUsing 'Stub' ReadLine";
	my $perl_rl = $ENV{PERL_RL} // '';
	print STDERR " ('$perl_rl' not available)" if $perl_rl;
	warn ".\nBetter install some 'real' implementation...\n\n";
	last
    }
    warn "Wat? unknown $rli\n"
};

# used to have 2x 012x and then rand << 48 -- low digits did not change...
#$synmsg = sprintf "%08x%08x%08", rand 1 << 32, rand 1 << 32, rand 1 << 32;

$synmsg = pack 'u', pack('LLL', rand 1 << 32, rand 1 << 32, rand 1 << 32);
# drop leading "length" character and trailing newline. "a" for '$synmsg' below
$synmsg = substr $synmsg, 1, 16; $synmsg =~ tr/'/a/;

### code-too-remote ###
my $S;
### end ###
undef $_;
socketpair $S, $_, 1, 1, 0 or pdie "socketpair:"; # pf_unix 1, sock_stream 1

my $pid = fork;
unless ($pid) {
    close $S; # close this early, close-on-exec will close $_
    undef $S;
    pdie "fork:" unless defined $pid;
    # child (cont.)
    open STDIN, '<&', $_ or pdie;
    open STDOUT, '>&', $_ or pdie;
    $ENV{LC_ALL} = $ENV{LANG} = 'C';
    setpgrp; # no SIGINT from "termios"
    warn "running '@ARGV'\n";
    syswrite STDOUT, '.ready.' or pdie;
    exec @ARGV;
    exit
}
#parent
close $_;
sysread $S, $_, 128;
undef $S, die "error while waiting child proc to initialize"
  unless $_ eq '.ready.';
warn "sending service code to 'remote'\n";
open I, '<', $0 or undef $S, die "opening '$0': $!";
$0 = 'rcli';
while (<I>) {
    if (/code[-]too[-]remote/) {
	print $S '# line ', $. + 1, "\n";
	while (<I>) {
	    last if /^### end ###\s/;
	    print $S $_
	}
    }
}
close I;

print $S "\$synmsg = '$synmsg';";

# for e.g. ls -C -- "WINCH" maeby later, but if good enough already...
$_ = $ENV{LINES};   print $S '$ENV{LINES}=', $_, "\n" if defined $_;
$_ = $ENV{COLUMNS}; print $S '$ENV{COLUMNS}=', $_, "\n" if defined $_;

#print $S "\$rorl = '$rhost';\n";
print $S "remote_main\n";
print $S "__END__\n";

select $S; $| = 1;
select $term->OUT || \*STDOUT;
$| = 1;
sysread $S, $_, 15;
undef $S, die "error in sending code to 'remote'\n"
  unless $_ eq '.code received.';
warn "code sent\n";
print "Press TAB twice for commands\n";

# this winch could utilize RESTART (or not) #
#my $winch_received = 0; # interested before sending commands
#$SIG{WINCH} = sub { $winch_received = 1; };

my $mr_char = '';
$SIG{INT} = sub { return unless $mr_char; $mr_char = '!' };

# remote has separate impl, where $S -> STDOUT ($S = \*STDIN "breaks" common)
sub write_out($) {
    #warn "$rorl: $_[0] - ", length $_[0], "\n";
    syswrite $S, pack 'wa*', length $_[0], $_[0]
}

END {
    if (defined $S) {
	write_out 'exit';
	close $S;
	select undef, undef, undef, 0.1;
	print "exit\n"
    }
};

### code-too-remote ###
sub uz_eintr ($)
{
    #warn "$rorl: uz $_[0] $!\n";
    pdie "rlen 0" if defined $_[0];
    pdie $! unless $! == EINTR
    # continue after eintr #
}
sub read_in ()
{
    my $rlen;
    while (1) {
	$rlen = sysread $S, $_, 8192;
	last if $rlen;
	uz_eintr $rlen;
    }
    my $mlen; ($mlen, $_) = unpack 'wa*', $_;
    if ($mlen < 128) { $rlen -= 1 }
    elsif ($mlen < 16384) { $rlen -= 2 }
    # v these are (already) mostly unexpected v #
    elsif ($mlen < 2097152) { $rlen -= 3 }
    else { $rlen -= 4 }
    #warn "/$rorl:---$_---$rorl/";
    #warn ("$rorl: xxx ", $_, "\n") if $mlen < $rlen;
    #warn ("$rorl: -- $rlen $mlen --\n");
    while ($rlen < $mlen) {
	my $r = sysread $S, $_, 4096, $rlen;
	unless ($r) {
	    uz_eintr $r;
	    next
	}
	$rlen += $r;
	#warn ("$rorl -= $rlen $mlen #-\n");
    }
    $mlen
}
### end ###

sub mread_in ()
{
    $mr_char = '.';
    while (1) {
	my $mlen = read_in;
	last if $mlen == 0;
	syswrite $S, $mr_char;
	print $_
    }
    $mr_char = ''
}

sub compl_remote($$)
{
    return () if ord($_[1]) == 45; # '-'
    write_out " @_";
    read_in;
    #warn ":$_:";
    return split "\0"
}

sub compl_remote_dirs { return compl_remote 'd', $_[1] }
sub compl_remote_files { return compl_remote 'f', $_[1] }

sub compl_local_dirs {
    return grep { $_ = "$_/" if -d $_ } glob "$_[1]*"
}
sub compl_local_files {
    return grep { $_ = "$_/" if -d $_; 1 } glob "$_[1]*"
}

sub compl_none { () }

my %ccmds =
  ( cd   => \&compl_remote_dirs,
    lcd  => \&compl_local_dirs,
    env  => sub { return compl_remote 'e', $_[1] },
    echo => \&compl_none, # pitää kattoo tarvitaanko (tai sit varexp)
    cat  => \&compl_remote_files,
    ls   => \&compl_remote_files,
    lls  => \&compl_local_files,
    less => \&compl_remote_files,
    grep => \&compl_remote_files,
    get  => \&compl_remote_files,
    put  => \&compl_local_files,
    head => \&compl_local_files,
    tail => \&compl_local_files,
    ps   => sub { qw/-x -f -w -ww/ },
    pwd  => \&compl_none,
    truncate => \&compl_remote_files,
    openssl  => \&compl_remote_files,
    history  => \&compl_none,
    hostname => \&compl_none # change to 'host' which collects more info
  );
my @ccmds = sort keys %ccmds;

sub _rl_complete($$$) {
    #warn "\n | " . (join " | ", @_) . " |\n";
    my ($text, $line, $start) = @_;
    if ($start == 0) {
	return grep { index ($_, $text) == 0 } @ccmds;
    }
    $line =~ /(\S+)/;
    my $sub = $ccmds{$1};
    no warnings;
    $readline::rl_completer_terminator_character = ''; # ...::Perl
    $term->Attribs->{completion_suppress_append} = 1;  # ...::Gnu
    use warnings;
    return () unless defined $sub;
    return $sub->($1, $text)
}

read_in;
print "pwd: $_\n";
s:.*/::;
my $prompt = "$pnl$_/» ";

my @list;
my %lcmds =
  (
   lcd => sub {
       my $d = $list[1] // '';
       my $t = ($d? chdir($d): chdir)? 'succeeded': "failed: $!";
       print "local chdir to '$d' $t\n";
       print 'local dir now: ', POSIX::getcwd()
   },
   lpwd => sub { print POSIX::getcwd() },
   lls => sub { $list[0] = 'ls'; push @list,'-CF' if @list == 1; system @list },
   put => \&l_put_file,
   history => sub { print "@list: oottaa toteutusta" },
   #':' => sub { write_out ':' },
   exit => sub { exit }
  );

my ($starttime, $prevtime, $currtime);
sub ft_progress ($$) {
    my $m = $_[1] - $_[0];
    my $t = $currtime - $starttime;
    my $s = int ($m / $t);
    my $p = ($m / $_[1]) * 100;
    # \033[K: clear from cursor to end of line -- works most of the cases
    printf "  %d/%d (%d%%) %ds, %d bytes/s\033[K\r", $m, $_[1], $p, $t, $s;
    $prevtime = $currtime;
}

sub l_get_file () {
    read_in;
    print($_), return unless /^\d/;
    my ($p, $s, $fn) = split / /, $_, 3; $p &= 0777; $s += 0;
    if (-e $fn) {
	print "'$fn' exists. skipping";
	syswrite $S, 'x';
	return
    }
    my $tfn = "$fn.uus";
    unless (open F, '>', $tfn) {
	print "Cannot write '$fn': $!\n";
	syswrite $S, 'x';
	return
    }
    printf "File: '%s', perm 0%03o, size %d\n", $fn, $p, $s;
    chmod $p, $tfn;
    syswrite $S, '.';
    my $t = $s;
    $mr_char = '.';
    $starttime = $prevtime = time;
    while ($mr_char eq '.') {
	my $r = sysread $S, $_, $s > 65536? 65536: $s;
	unless ($r) {
	    uz_eintr $r;
	    next
	}
	my $w = syswrite F, $_;
	pdie __LINE__ . ": $w not $r" unless $w == $r;
	$s -= $r;
	last if $s == 0;
	$currtime = time;
	ft_progress $s, $t if $currtime != $prevtime
    }
    close F;
    if ($s == 0) {
	rename $tfn, $fn # fixme check success message if failed
    } else {
	write_out ':'; # interrupt, or no-op cmd if remote sent everything
	print "\r*interrupt*"
    }
    ft_progress $s, $t if $starttime != $prevtime;
    while (1) {
	my $r = sysread $S, $_, 16384, 16;
	unless ($r) {
	    uz_eintr $r;
	    next
	}
	last if index($_, $synmsg) >= 0;
	$_ = substr $_, -16
    }
}

sub ft_buffered ($$) {
    my $m = $_[1] - $_[0];
    my $t = $currtime - $starttime;
    my $p = ($m / $_[1]) * 100;
    printf "  buffered %d/%d (%d%%) %ds\r", $m, $_[1], $p, $t;
    $prevtime = $currtime
}

sub l_put_file () {
    s/\S+\s+//;
    my @st = stat;
    print("'$_': no such file\n"), return unless -f _;
    print("'$_' unreadable\n"), return unless -r _;
    print("'$_' empty (truncate -s 0 it)\n"), return unless -s _;
    my $fh;
    unless (open $fh, '<', $_) {
	print "Failed to open '$_': $!\n";
	return
    }
    my $p = $st[2] & 0777;
    my $s = $st[7];
    my $fn = $_;
    s:.*/::; # basename
    write_out "put $p $s $_";
    last unless sysread $S, $_, 4096;
    print($_), return unless $_ eq '.';
    printf "File: '$fn', perm 0%03o, size %d\n", $p, $s;
    my $t = $s;
    $mr_char = '.';
    $starttime = $prevtime = time;
    while ($mr_char eq '.') {
	my $r = sysread $fh, $_, 4096;
	unless ($r) {
	    uz_eintr $r;
	    next
	}
	my $w = syswrite $S, $_;
	$currtime = time;
	last unless defined $w;
	pdie __LINE__ . ": $w not $r" unless $w == $r; # unlikely!
	$s -= $r;
	last if $s == 0;
	ft_buffered $s, $t if $currtime != $prevtime;
    }
    $mr_char = '';
    if ($s == 0) { # sent all of a file
	ft_buffered $s, $t if $starttime != $prevtime;
	while (1) {
	    my $r = sysread $S, $_, 4096;
	    unless ($r) {
		uz_eintr $r;
		next
	    }
	    # check char for success/fail maeby
	    return;
	}
	syswrite $S, $synmsg; # to avoid interrupt confusion w/ just a few byte
	return
    }
    # else interrupted #
    print " *interrupt ", $t - $s, ' -- draining buffer*';
    my $ifd = fileno $S;
    my $rin = '';
    vec ($rin, $ifd, 1) = 1;
    while (1) {
	my $rout;
	select $rout = $rin, undef, undef, 0.5;
	print '.';
	if (vec ($rout, $ifd, 1)) {
	    my $r = sysread $S, $_, 4096;
	    unless ($r) {
		syswrite $S, '!';
		uz_eintr $r;
		next
	    }
	    # could check char.
	    last
	}
	syswrite $S, '!'
    }
    syswrite $S, $synmsg;
}

my %rio =
  ( ls => sub { mread_in },
    cd => sub { read_in; s:(.*?/)::; $prompt = "$pnl$1» "; print $_ },
    get => \&l_get_file,
  );

$term->ornaments(0);

while ( defined ($_ = $term->readline($prompt)) ) {
    next unless /\S/;
    #warn "rline: '$_'\n";
    s/\s+$//; s/^\s+//;
    $term->addhistory($_);
    if (s/^!//) {
	my $sh = $ENV{SHELL} // 'sh';
	system($sh, '-i'), next unless $_;
	system $sh, '-c', $_;
	next
    }
    @list = split / /, $_, 2;
    my $lcmd = $lcmds{$list[0]};
    $lcmd->(), next if defined $lcmd;
    print("'$list[0]': ei ole\n"), next unless defined $ccmds{$list[0]};
    write_out $_;
    my $sub = $rio{$list[0]};
    $sub->(), next if defined $sub;
    read_in;
    print $_
}

__END__
### code-too-remote ###
$rorl = 'remote';
$0 = 'rclid';
$S = \*STDIN;
my @list;

sub write_out($) {
    #warn "$rorl: $_[0] - ", length $_[0], "\n";
    syswrite STDOUT, pack 'wa*', length $_[0], $_[0]
}

sub exec_null_stdin ()
{
    # POSIX::open() & POSIX::dup() do not come with FD_CLOEXEC...
    pipe P, W or pdie 'pipe:';
    my $pid = fork;
    close W, return if $pid; # parent
    pdie 'fork:' unless defined $pid;
    # child #
    open STDIN, '<', '/dev/null';
    open STDOUT, '>&W';
    exec @list;
    exit
}

sub run_cmd () {
    exec_null_stdin;
    while (1) {
	my $rlen = sysread P, $_, 8188;
	last if $rlen <= 0;
	write_out $_;
	sysread STDIN, $_, 8188; # gets one '.' (or 'x')
	last unless $_ eq '.';
    }
    close P;
    wait;
    write_out ''
}

sub run_qxish () {
    exec_null_stdin;
    my $rlen = sysread P, $_, 8188;
    if ($rlen) {
	while (1) {
	    my $r = sysread P, $_, 8192, $rlen;
	    last unless $r;
	    # cap max 16380
	    last if length > 8192;
	    $rlen += $r
	}
    }
    close P;
    wait;
    chomp;
    write_out $_
}

#sub MSG_DONTWAIT { 64 } # < one linux, one freebsd: 128 ...
use Socket qw/MSG_DONTWAIT/;

sub r_put_file () { # howto do put_files ? last char '.' and '*?[' in string
    s/\S+\s+//;
    my @st = stat;
    write_out("'$_': no such file"), return unless -f _;
    write_out("'$_' unreadable"), return unless -r _;
    write_out("'$_' empty"), return unless -s _;
    my $fh;
    unless (open $fh, '<', $_) {
	write_out "Failed to open '$_': $!";
	return
    }
    s:.*/::; # basename
    write_out "$st[2] $st[7] $_";
    sysread STDIN, $_, 4096; # expect one '.'
    return unless $_ eq '.';
    while (1) {
	my $r = sysread $fh, $_, 4096;
	last unless $r;
	my $w = (send STDOUT, $_, MSG_DONTWAIT) // 0;
	if ($w != $r) {
	    my $c = '';
	    recv STDIN, $c, 32, MSG_DONTWAIT;
	    last if $c; # interrupt #
	    $w += syswrite STDOUT, $_, (length) - $w, $w;
	}
	pdie __LINE__ . ": $w not $r" unless $w == $r; # unlikely!
    }
    syswrite STDOUT, $synmsg
}

sub r_get_file () {
    @list = split / /, $_, 4;
    my $fn = $list[3];
    syswrite(STDOUT, "'$fn': file exists"), return if -e $fn;
    my $tfn = "$fn.uuz";
    unless (open F, '>', $tfn) {
	syswrite STDOUT, "Cannot write '$fn': $!";
	return
    }
    chmod $list[1], $tfn;
    syswrite STDOUT, '.';
    my $s = $list[2];
    while (1) {
	my $r = sysread $S, $_, $s > 16384? 16384: $s;
	#warn "rrr $r $s\n" if $r < 1000;
	last unless $r;
	my $w = syswrite F, $_;
	pdie "$w not $r" unless $w == $r; # unlikely!
	$s -= $r;
	last if $s == 0;
	if ($r < 3) {
	    warn " $r -- $s '$_'";
	    unless (/[^!]/) {
		# short msg all '!'s: "interrupt" #
		syswrite STDOUT, '!'; # so inform remote
		last
	    }
	}
    }
    close F;
    if ($s == 0) {
	rename $tfn, $fn; # fixme: msg if failz
	syswrite STDOUT, '.'; # and inform remote
    }
    while (1) {
	my $rlen = sysread $S, $_, 16384, 16;
	last unless $rlen;
	last if index($_, $synmsg) >= 0;
	$_ = substr $_, -16
    }
}

my @envk = sort keys %ENV;

sub complete() {
    #warn scalar @list, " $list[0]";
    if ($list[1] eq 'e') {
	return @envk if @list == 2;
	return grep { index ($_, $list[2]) == 0 } @envk;
    }
    my $t = (@list == 3)? $list[2]: '';
    return grep { $_ = "$_/" if -d $_; 1 } glob "$t*" if $list[1] eq 'f';
    return grep { $_ = "$_/" if -d $_ } glob "$t*"
}

my %hash =
  ( '' => sub { write_out join("\0", complete) },
    ':' => sub {}, # noop
    pwd => sub { write_out POSIX::getcwd() },
    cd => sub {
	#s/\S+\s+//; instead of what is below now ?
	shift @list;
	my $d = join ' ', @list;
	my $t = ($d? chdir($d): chdir)? 'succeeded': "failed: $!";
	$_ = POSIX::getcwd(); s:.*/::;
	write_out "$_/chdir to '$d' $t"
    },
    ls => sub {
	$list[1] = '-CF' unless defined $list[1];
	run_cmd
    },
    env => sub {
	if (defined $list[1]) {
	    my $val = $ENV{$list[1]} // '(unset)';
	    write_out "$list[1]=$val"
	}
	else { write_out join('  ', @envk) }
    },
    echo => sub { s/\S+\s+//; write_out $_ },
    get => \&r_put_file,
    put => \&r_get_file,
    exit => sub { exit 0 }
  );

#use Data::Dumper; warn Dumper(\%hash);

sub remote_main () {
    syswrite STDOUT, ".code received.";
    write_out POSIX::getcwd();
    #print STDERR $synmsg, "\n";
    while (1) {
	read_in;
	#@list = split / /, $_, 2;
	@list = split / /, $_;
	my $sub = $hash{$list[0]};
	$sub->(), next if defined $sub;
	run_qxish
    }
}
