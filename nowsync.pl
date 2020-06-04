#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ nowsync.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2015 Tomi Ollila
#	    All rights reserved
#
# Created: Sat 16 May 2015 11:40:42 EEST too
# Last modified: Thu 04 Jun 2020 22:08:15 +0300 too

=encoding utf8

=head1 NAME

B<nowsync.pl> -- continuously update directory tree to remote hosts

=head1 SYNOPSIS

B<nowsync.pl> I<[--help]> I<[--exclude re [--exclude re...]]> I<[--limit num]>
    I<[--max-size size]> I<[-T]>
    I<[--ssh-command cmd  [args]]> I<[--perl-command cmdline]>
    I<path>  I<remote:path [remote:path...]>

=head1 DESCRIPTION

I<Nowsync> synchronizes contents of a given local directory recursively to
one or more remote directories and then continues updating file and directory
changes to these remote systems. inotify(7) is used to recognize changes
after initial sync (which probably restricts local host to be linux machine
but remote host can also be running some other operating system).

This tool operates by sending perl (5.8.1+) program to all of the remote
systems and then communicating with it. In the current version the
communication protocol is very simple, yet effective for basic use. But
check B<BUGS> below to be aware of the corner cases...

As of today this is mainly targeted for developer use and the "diagnostics"
output look like so. Devote one terminal window for monitoring the events
and traffic with the remote hosts. If it is unsuitable for having one terminal
reserved for this use, use e.g. dtach(1), screen(1), tmux(1) to detach
I<nowsync> from terminal (and if you want to store logs, consider using
script(1)).

=head1 OPTIONS

Minimal command line is

=over 4

B<nowsync.pl> B<local-dir> B<[user@]remote-host:remote-dir>

=back

Which will just sync everything from B<local-dir> to this one remote dir,
using ssh tunnel for the transport.

Usually there are some files/directories that user may want to exclude
from the list; an example of such options:

=over 6

B<--exclude '^[.]git$'> B<--exclude '[~#]'>

=back

The exclude option(s) are basically in extended reqular expression format,
and in the above line single quotes are used to escape the options from
shell expansion. The above excludes would make I<nowsync> exclude any
directory (or file) which name is '.git' and also any file (or directory)
name that contains character '~' or '#'. The match is made to the filename
without the leading directories -- for example B<--exclude a/b> would never
match anything and B<'^[.]git$'> matches any subdirectory named B<.git>.

To avoid accidental execution where B<local-dir> may cover too wide of
a directory tree (like B<$HOME> directory), there is limit of how small
directory tree (in number of files, 100 by default) must be to be considered
as one user would normally use with this tool.
If this limit is too small, command line option

=over 6

B<--limit num>

=back

can be used to lift the value.

Also, copying huge files over the links may be problematic. Therefore by
default all files larger than 65536 bytes are not sent over. To allow
larger files to be copied, use

=over 6

B<--max-size size>

=back

command line option.

There is yet one limitation option available:

=over 6

B<-T>

=back

which limits file selection to "text" files only (perl heuristic guess).

Sometimes the default ssh command B<ssh> is not enough; it may be named
differently, or it may not be in path -- or there is more options to be
given to it. the option

=over 6

B<--ssh-command command  [args]>

=back

can be used to change this. Any 2 consecutive spaces (' '' ') in the
command-argument string are to be used to split args from command and to
other args; this is useful when one wants to add e.g. B<-oProxyCommand>
option -- the option value itself contains spaces so inside that there are
only single spaces, but to separate this from other args 2 spaces are to
be used. E.g.

 --ssh-command 'ssh  -p  2222  -oProxyCommand=ssh pxy.example.org -W %h:%p'

Another useful "proxy" pattern is:

 --ssh-command 'ssh  -p  2222  -T  user@pxy.example.org  ssh'

The remote synchronization server is a perl program whose code is sent over
the communication link after the link has been established. As with ssh the
default remote perl command line 'B<perl ->' may not be sufficient, e.g. perl
is not found in remote B<$PATH>. The option

=over 6

B<--perl-command cmdline>

=back

will make a difference there. A good candidate for this option is
B<--perl-command /usr/local/bin/perl -> -- note the trailing dash (-) -- it
is needed for perl to read then program code from its standard input. As this
is the command given to ssh to be executed on remote host (using the login
shell of the user), anything that the shell can handle can be sent there,
should there be need for anything special.

=head1 NOTES

File copy is done by first writing the file using "temporary" name at the
destinations (file name suffixed with process id) and after write is complete
file is closed and renamed to the target file name. This means the file is
updated "atomically" -- the old references to the old file (if any) will keep
using the old file which no longer hold the same name and any new file access
will be referencing the new file (with the same name).

=head1 BUGS

The quality of I<nowsync> is adequate for most of the purposes. To make this
perfect would require significant amount of time and resources. Perhaps
some of the simplest/most needed misfeatures are fixed, either by sudden
burst of enthusiasm or use case for the features arise.

=over 2

=item *

If file changes while it is copied over the remotes it will still first
written fully to the remote (and then re-sent) -- in case file gets shorter
to match the original size rest of the "file content" is read from /dev/zero.

=item *

No files not existing locally is not initially deleted from remotes (this
is a feature). Just that if there is file in remote host in place of a
directory to be copied there first creation of directory will fail and
then no files to that directory are copied over.

=item *

Moving directory from outside of the watched tree or from ignored name
to non-ignored one will just create the directory to the remotes
without any of the content there may be in local filesystem.

=item *

Moving directory to outside of watched tree or to ignored name causes
attempt to directory to be deleted as a file, which fails -- changing
this to to full remote directory removal (system "rm -rf") is just
something that has not been implemented. yet (probably change to
inotify handling in perl and internal restructuring is done before that).

=item *

File may be created but if no data is written to it remotes are not notified
of its existence. Later if that file is deleted, request to remove it is
sent to remotes -- and remotes will send back message to inform that file
deletion failed.

=item *

Currently this program is using inotifywait(1) for getting events; as
it is not providing cookie information when renaming file one cannot
be absolutely sure that the moved_from, moved_to pair of events refer
to the same file and file rename target may contain wrong data. The
probability of this happening is very low, though
(lower than other bugs...).

=item *

If connections to remote hosts break local host will not notice it until
more filesystem changes have happened -- basically this program will exit
when it encounters failure trying to send new data to remotes.

=item *

Hard links not noticed, symbolic links not (yet) supported.

=item *

More of the successive events could be cached and same events suppressed
to one.

=back

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under the
same terms as the Perl 5 programming language system itself:

Terms of Perl itself

=over 4

=item a)

the GNU General Public License as published by the Free
Software Foundation; either version 1, or (at your option) any
later version, or

=item b)

the "Artistic License"

=back

=head1 AUTHOR

Tomi Ollila -- too ät iki piste fi

=head1 VERSION

1.0 (2015-06-11)

=cut

# History
#
# 1.1  2015-06-14  txtonly bug fix, 4th iteration of the name
#
#  Checking whether with -T whether file is (ASCII or UTF-8) text file
#  used wrong "variable" for the file; in addtion that it did not work
#  correctly it broke futher checks on same file. Additionally the check
#  was in wrong place, effectively blocking all subdirectories.
#
# 1.0  2015-06-11  initial release, 3rd iteration of the name
#

# FUTURE PLANS
#   Note: these may hinder bug fixes...
#
# Add option for file versioning in the remote (note to self: append-only zip?)
#
# Replace inotifywait(1) with perl inotify code (if this happens, some
# of the bugs above is probably easier to fix...

# And remember (from http://en.wikiquote.org/wiki/Talk:Larry_Wall )
# Q. Why is this so clumsy?
# A. The trick is to use Perl's strengths rather than its weaknesses.

### code-too-remote ###
use 5.8.1;
use strict;
use warnings;

my $rorl;
sub pdie (@) {
    die "$rorl: $!\n" unless @_;
    die "$rorl: @_ $!\n" if $_[$#_] =~ /:$/;
    die "$rorl: @_\n";
}
sub pwarn(@)
{
    warn("$rorl: @_ $!\n"), return if $_[$#_] =~ /:$/;
    warn "$rorl: @_\n";
}
### end ###
$rorl = 'local';

use Socket;

# using inotifywait is simpler than doing inhouse code for that :D ...
# just that it is somewhat limited (no cookies ([n]or subsecond time))
my $inotifywait;
foreach (split /:/, $ENV{PATH}) {
    my $p = $_ . '/inotifywait';
    $inotifywait = $p, last if -x $p;
}

# Note: Init (time) error messages are Capitalized. Runtime not...

die "Cannot find 'inotifywait'. Install inotify-tools for that.\n"
  unless defined $inotifywait;

unless (@ARGV) {
    my $n = (ord $0 == 47)? ( ($0 =~ /([^\/]+)$/), $1 ): $0;

    die "\nUsage: $n [--help] [--exclude re [--exclude re...]]\n",
      "          [--limit num] [--max-size size] [-T] \n",
      "          [--ssh-command cmd  [args]] [--perl-command cmdline]\n",
      "          {path} {remote:path} [remote:path...]\n\n";
}

if ($ARGV[0] eq '-h' or $ARGV[0] eq '--help') {
    require Pod::Usage; Pod::Usage->import(qw/pod2usage/);
    pod2usage(-verbose => 2, -exitval => 'NOEXIT', -noperldoc => 0);
    exit !$_[0];
}

my (@excludes, $limit, $max_size, $txtonly);

# same for all. could have separate opts given just before each remote:paths...
my @ssh_command = qw/ssh/;
my $perl_command = 'perl';

#my $daemon_logfile;
my $path;
while (@ARGV > 1) {
    $_ = shift;

    $txtonly = 1, next if $_ eq '-T';
    $limit = shift, next if $_ eq '--limit';
    $max_size = shift, next if $_ eq '--max-size';
    push(@excludes, shift), next if $_ eq '--exclude';
    @ssh_command = (split /  /, shift), next if $_ eq '--ssh-command';
    $perl_command = shift, next if $_ eq '--perl-command';
    #set_daemonlogfile(shift), next if $_ eq '--daemon-log';

    $limit = $1, next if /^--limit=(.*)/;
    $max_size = $1, next if /^--max-size=(.*)/;
    push(@excludes, $1), next if /^--exclude=(.*)/;
    @ssh_command = (split /  /, $1), next if /^--ssh-command=(.*)/;
    $perl_command = $1, next if /^--perl-command=(.*)/;
    #set_daemonlogfile($1), next if /^--daemon-log=(.*)/;

    die "'$_': unknown option\n" if $_ =~ /^-/;
    $path = $_;
    last;
}

$txtonly = 0 unless defined $txtonly;

#print((join "\n", @ssh_command), "\n"); exit;
#print $_, "\n" foreach (@ARGV);

sub int_arg($$$)
{
    if (defined $_[0]) {
	die "$_[2] '$_[0]' not just a (positive) number\n"
	  unless $_[0] =~ /^\d+$/;
	$_[0] = $_[0] + 0;
    }
    else { $_[0] = $_[1]; }
}

int_arg $limit, 100, 'limit';
int_arg $max_size, 65536, 'max size';

die "No paths given\n" unless defined $path;

if ($path =~ s,^~(?=/|$),,) {
    $path = $ENV{HOME} . $path;
}   #print "$path\n"; exit 0;

pdie "'$path': not a directory" unless -d $path;
pdie "'$path': not accessible by current user" unless -x $path;

$path = $path.'/' unless $path =~ /\/$/;

foreach (@ARGV) {
    die "'$_': not in format [user@]host:path\n" unless /:/;
}

my @inow_eopt;
if (@excludes) {
    @inow_eopt = ( '--exclude', (@excludes > 1)?
		   '(' . (join '|', @excludes) . ')': $excludes[0] );

    $_ = qr/$_/ foreach (@excludes);
}
#print "@inow_eopt\n"; print "@excludes\n"; exit 0;

sub chkexcludes ($) {
    #print "chkexcl: $_[0]\n"; # return 0;
    return 0 if $_[0] eq '.' or $_[0] eq '..';
    foreach (@excludes) {
	return 0 if $_[0] =~ $_;
    }
    return 0 if index($_[0], "\n") >= 0;
    return 1;
}

# alldirs will be used (more) if/when inotify is handled internally...
my @alldirs;
my @list;

sub scan($); # defined for recursion
sub scan($)
{
    unless (opendir D, $path . $_[0]) {
	warn "opendir '$path/$_[0]': $! (skipping)";
	return;
    }
    my @files = sort grep { chkexcludes $_ } readdir D;
    closedir D;
    #print "--- $_[0] @files\n"; system qw/pwd/; system qw/ls -l/;
    my (@dirs, @st);
    foreach (@files) {
	my $file = $_[0] . $_;
	if (-l $path . $file) {
	    pwarn "skipping symlink '$file'";
	    next;
	}
	unless (-f _) {
	    push @dirs, $file if -d _;
	    #print "xxx $_[0] '$file'\n" unless -d $file;
	    next;
	}
	if ($txtonly and -B _) {
	    pwarn "skipping presumably binary file '$file'";
	    next;
	}
	@st = stat _;
	my $size = $st[7];
	if ($size > $max_size) {
	    pwarn "file '$file' skipped: size $size (> $max_size)";
	    next;
	}
	push @list, #[ $st[2] & 0777, $st[9], $st[7], '//', $file ];
	  sprintf "%o %ld %ld // %s", $st[2] & 0777, $st[9], $size, $file;
    }
    undef @files;
    foreach (@dirs) {
	@st = stat $path . $_;
	push @list, #[ $st[2] & 0777 | 01000, $st[9], $st[7], '//', $_ ];
	  sprintf "%o %ld %ld // %s", $st[2] | 01000, $st[9], $st[7], $_;
    }
    foreach (@dirs) {
    	push @alldirs, $_;
    	scan $_ . '/';
    }
}

push @alldirs, '.';
scan './';

#foreach (@alldirs) { print $_, "\n"; }; exit 0;

push @list, "//eol//\n";
pwarn "# of files (and dirs): $#list";
die "Found too many files ($#list) (limit $limit).\n" .
  "Use '--limit' command line option to increase limit\n"
  if @list >= $limit;


my @remotes;

eval 'END { $SIG{ALRM} = sub { pwarn "nowsync exit"; exit 0; };
	select undef, undef, undef, 0.1;
	$SIG{TERM} = q"IGNORE"; kill q"TERM", 0;
	alarm 2; 1 while (wait >= 0); alarm 0; $SIG{ALRM}()}';

$SIG{PIPE} = sub { pwarn "broken pipe (one of the ssh connections)"; exit 0; };
$SIG{HUP} = $SIG{TERM} = $SIG{INT} = sub { exit 0; };

foreach (@ARGV) {
    my ($fd1, $fd2);
    socketpair $fd1, $fd2, PF_UNIX, SOCK_STREAM, 0
      or pdie "socketpair() failed:";

    my ($rhost, $path) = split /:/, $_, 2;

    select $fd1; $| = 1; select STDOUT;

    my $pid = fork();
    pdie "fork() failed:" unless defined $pid;
    if ($pid == 0) {
	# child
	close $fd1; # close this early, close-on-exec will close $fd2
	open STDIN, '<&', $fd2 or pdie;
	open STDOUT, '>&', $fd2 or pdie;
	$ENV{LC_ALL} = $ENV{LANG} = 'C';
	warn "running '", join("' '", @ssh_command),
	  "' '-T' '$rhost' '$perl_command - nowsync-server'\n";
	syswrite $fd2, 'ready.' or pdie;
	# --ssh-command options for development & testing (note spacing):
	# --ssh-command='sh  -c  cat >&2'  # to see what code is sent remote
	# --ssh-command='perl  -'          # to test on local fs
	exec @ssh_command, '-T', $rhost, "$perl_command - nowsync-server";
	exit 1;
    }
    #parent
    close $fd2;
    sysread $fd1, $_, 128;
    die "error while waiting child proc to initialize\n" unless $_ eq 'ready.';
    warn "sending service code and remote path to $rhost...\n";
    open I, '<', $0 or pdie "opening '$0':";
    while (<I>) {
	if (/code[-]too[-]remote/) {
	    print $fd1 '# line ', $. + 1, "\n";
	    while (<I>) {
		last if /^### end ###\s/;
		print $fd1 $_;
	    }
	}
    }
    close I;
    print $fd1 "\$rorl = '$rhost';\n";
    print $fd1 "remote_main\n";
    print $fd1 "__END__\n";
    sysread $fd1, $_, 128;
    die "error in sending code to $rhost\n" unless $_ eq 'code received.';
    syswrite $fd1, "-\n-\n::path:: $path\n";
    sysread $fd1, $_, 128;
    die "error in receiving 'path' notification from $rhost\n"
      unless $_ =~ /^path /;
    exit unless $_ eq 'path ok.'; # alternative to exit: close just this conn...
    warn "connection sync with $rhost done\n";
    push @remotes, [ $fd1, "$rhost:$path" ];
}

# <- '#' there fools emacs cperl mode to do syntax highlighting below \o/
=begin comment
### code-too-remote ###
sub mkmissingdir($$)
{
    return if -d $_[1];
    unless (mkdir $_[1]) {
	pwarn "cannot create directory $_[1]:";
	return;
    }
    chmod (($_[0] & 0777), $_[1]) or
      pwarn "chmod directory $_[1] failed:";
}

sub copy_data($)
{
    my $buf;
    my $rlen = sysread STDIN, $buf, $_[0];
    pdie "rlen $rlen" unless $rlen > 0;
    my $wlen = syswrite O, $buf, $rlen;
    if ($rlen != $wlen) { pdie("syswrite: '$rlen' != '$wlen':"); }
    return $rlen;
}

sub perm_and_mtime($$$)
{
    chmod oct($_[0]), $_[2] or pwarn "failed to chmod $_[0] $_[2]:";
    utime $_[1], $_[1], $_[2] or pwarn "failed to utime $_[2]:";
}

sub remote_main ()
{
    $| = 1;
    syswrite STDOUT, 'code received.';
    while (<STDIN>) {
	if (/::path:: (.*)/) {
	    if ($1 ne '.' and $1 ne '') {
		unless (chdir ($1)) {
		    syswrite STDOUT, 'path cd failed.';
		    pdie "Cannot chdir to $1:"
		}
	    }
	    last
	}
    }
    syswrite STDOUT, 'path ok.';

    # get filelist, "perm mtime size name" # spaces are but no newlines allowed
    my @list;
    my $imatches = 0;
    while (<STDIN>) {
	last if m|^//eol//|;
	chomp;
	my ($perm, $mtime, $size, $sep, $name) = split ' ', $_, 5;
	if ($sep ne '//') {
	    pwarn "4th (intr chk sep) field '$sep' is not '//'";
	    next;
	}
	if (! defined $name or $name =~ /^\s*$/) {
	    pwarn "filename is undefined or empty";
	    next;
	}
	if ($name =~ m,(?:^|/)[.][.](?:/|$), ) {
	    pwarn "filename '$name' has '..' components. skipping";
	    next;
	}
	$perm = oct $perm;
	if ($perm > 0777) { # directory
	    mkmissingdir $perm, $name;
	    next;
	}
	my @st = stat $name;
	if (! -f _) {
	    if (-e _) {
		pwarn "file '$name' exists but is not a file";
	    } else {
		push @list, $name;
	    }
	    next;
	}
	# in case of mtime differ could send back checksum and
	# if matches, other end could just send attrib request.
	if ($mtime != $st[9] or $size != $st[7]) {
	    push @list, $name;
	} else {
	    $imatches++;
	    chmod $perm, $name unless $perm == ($st[2] & 0777);
	}
    }
    push @list, "//eol//\n";
    #syswrite STDERR, join "\n", @list;
    syswrite STDOUT, join "\n", @list;
    pwarn '# of initially matched files (sans dirs):', $imatches;
    undef @list;

    # and now to request loop -- all responses to stderr for now...
    while (<STDIN>) {
	chomp;
	pwarn $_;
	my $c = chr ord;
	if ($c eq 'c') { # copy
	    my (undef, $perm, $mtime, $size, $sep, $name) = split ' ', $_, 6;
	    #pwarn "$size - $name";
	    # XXX we may remove the e.g. $sep checks from above code, too...
	    # XXX via temporary name... unlink (for perms) & rename
	    if (open O, '>', "$name.$$") {
		syswrite STDOUT, ':'; # like sh true
	    } else {
		pwarn "failed to open '$name.$$' for writing:";
		syswrite STDOUT, '!'; # like not
		next;
	    }
	    $size -= copy_data 32768 while ($size > 32768);
	    $size -= copy_data $size while ($size > 0);
	    close O;
	    rename "$name.$$", $name or pwarn "failed to rename $name.$$:";
	    perm_and_mtime $perm, $mtime, $name;
	    next;
	}
	if ($c eq 'r') { # move/rename
	    my (undef, $perm, $mtime, $sep, $names) = split ' ', $_, 5;
	    my ($old, $new) = split ' // ', $names;
	    rename $old, $new or pwarn "failed to rename $old to $new:";
	    perm_and_mtime $perm, $mtime, $new;
	    next;
	}
	if ($c eq 'm') { # mkdir
	    my (undef, $perm, $mtime, $sep, $name) = split ' ', $_, 5;
	    mkdir $name or pwarn "failed to mkdir $name";
	    perm_and_mtime $perm, $mtime, $name;
	    next;
	}
	if ($c eq 'd') { # remove/delete
	    s/^. //;
	    unlink $_ or pwarn("failed to unlink $_:");
	    next;
	}
	if ($c eq 'x') { # rmdir
	    s/^. //;
	    rmdir $_ or pwarn "failed to rmdir $_:";
	    next;
	}
	if ($c eq 'a') { # attrib/touch
	    my (undef, $perm, $mtime, $sep, $name) = split ' ', $_, 5;
	    perm_and_mtime $perm, $mtime, $name;
	    next;
	}
	last if $_ eq '//eof//';
	pdie "error: unknown input: '$_'";
	last;
    }
    print STDERR "$rorl: eof, quitting\n";
}

### end ###
=end comment

=cut

if ($path ne './') {
    chdir $path or pdie "Cannot chdir to '$path':";
}
undef $path;

sub copy_to($$)
{
    my ($name, $fd) = @_;
    #print $name, "\n"; return;
    my @st = stat $name;
    unless (@st) {
	pwarn "cannot stat '$name':";
	return;
    }
    my $size = $st[7]; # $size += 123; #<<- uncomment to test /dev/zero reading
    if ($size > $max_size) {
	pwarn "file '$name' skipped: size $size (> $max_size)";
	return;
    }
    unless (open I, '<', $name) {
	pwarn "cannot open '$name':";
	return;
    }
    printf $fd "c %o %ld %ld // %s\n", $st[2] & 0777, $st[9], $size, $name;
    sysread $fd, $_, 1;
    #print "($_)\n";
    close I, return unless $_ eq ':';
    # anonymous subroutine for variables from surrounding scope
    my $copy_data = sub ($) {
	my $buf;
	my $rlen = sysread I, $buf, $_[0];
	pdie "read error when reading '$name':" unless defined $rlen;
	if ($rlen == 0) {
	    pwarn "short read from '$name' -- continuing from /dev/zero";
	    unless (open I, '<', '/dev/zero') {
		pdie "cannot read from /dev/zero";
	    }
	    $rlen = sysread I, $buf, $_[0];
	    pdie "rlen $rlen:" unless $rlen > 0;
	}
	my $wlen = syswrite $fd, $buf, $rlen; # fd from outer context
	if ($rlen != $wlen) { pdie("syswrite: '$rlen' != '$wlen':"); }
	return $rlen;
    };
    $size -= $copy_data->(32768) while ($size > 32768);
    $size -= $copy_data->($size) while ($size > 0);
    close I;
}

# send local filelist, read responses of files to be copied over and copy those
# ... buffer response filelist so that reads do not interleave
foreach my $r (@remotes) {
    my $fd = $r->[0];
    print $fd join "\n", @list;
    my @l;
    while (my $f = <$fd>) {
	#print $f; #next;
	chomp $f;
	last if $f eq '//eol//';
	push @l, $f;
	#copy_to $f, $fd;
    }
    copy_to $_, $fd foreach (@l);
}

undef @list; # clear the list, that is (just that it should not be used anymore)

#@inow_eopt = ();
open P, '-|', qw/inotifywait -r -m -e close_write -e create -e delete
		 -e moved_from -e moved_to -e attrib --timefmt=%s
		 --format/, '%T %e %w // %f', @inow_eopt, '.'
  or pdie "Cannot run inotifywait:";

#sub ecopy_to_all($) { print "copy_to_all @_\n"; }
sub copy_to_all($) {
    foreach my $r (@remotes) {
	copy_to $_[0], $r->[0];
    }
}

#sub emkdir_all($) { print "mkdir_all @_\n"; }
sub mkdir_all($) {
    my @st = stat $_[0];
    pwarn("skipping move due to failure to stat $_[1]:"), return unless @st;
    my $perm = $st[2] & 0777;
    foreach my $r (@remotes) {
	my $fd = $r->[0];
	printf $fd "m %o %ld // %s\n", $perm, $st[9], $_[0];
	#print $fd "m $perm $st[9] // $_[0]\n";
    }
}

#sub eremove_all($) { print "remove_all @_\n"; }
sub remove_all($) {
    foreach my $r (@remotes) {
	my $fd = $r->[0];
	print $fd "d $_[0]\n";
    }
}

#sub ermdir_all($) { print "rmdir_all @_\n"; }
sub rmdir_all($) {
    foreach my $r (@remotes) {
	my $fd = $r->[0];
	print $fd "x $_[0]\n";
    }
}

#sub emove_all($$) { print "move_all @_\n"; }
sub move_all($$) {
    my @st = stat $_[1];
    pwarn("skipping move due to failure to stat $_[1]:"), return unless @st;
    my $perm = $st[2] & 0777;
    foreach my $r (@remotes) {
	my $fd = $r->[0];
	printf $fd "r %o %ld // %s // %s\n", $perm, $st[9], $_[0], $_[1];
	#print $fd "r $perm $st[9] // $_[0] // $_[1]\n";
    }
}

#sub eattrib_all($) { print "attrib_all @_\n"; }
sub attrib_all($) {
    my @st = stat $_[0];
    pwarn("skipping move due to failure to stat $_[1]:"), return unless @st;
    my $perm = $st[2] & 0777;
    foreach my $r (@remotes) {
	my $fd = $r->[0];
	printf $fd "a %o %ld // %s\n", $perm, $st[9], $_[0];
	#print $fd "a $perm $st[9] // $_[0]\n";
    }
}

# Note: currently no symlinks. create could check the type of file
# also, hardlinks are not recognized (full [device/]inode info would ne needed)

my $pevents = '';
my ($time, $events, $name); # here for continue block visibility
while (<P>) {
    print 'iw: ', $_;
    ($time, $events, $path) = split ' ', $_, 3;
    my ($dir, $name) = split ' // ', $path;
    chomp $name;
    next unless chkexcludes $name;
    if ($events =~ /CLOSE_WRITE/) {
	copy_to_all $dir . $name;
	next;
    }
    if ($events =~ /CREATE.*ISDIR/) {
	mkdir_all $dir . $name;
	next;
    }
    if ($events =~ /DELETE.*ISDIR/) {
	rmdir_all $dir . $name;
	next;
    }
    if ($events =~ /DELETE/) {
	remove_all $dir . $name;
	next;
    }
    if ($events =~ /ATTRIB/) {
	next if $pevents eq 'CREATE'; # not isdir one.
	attrib_all $dir . $name;
	next;
    }
    if ($events =~ /MOVED_TO/) { # but not after MOVED_FROM
	if ($events =~ /ISDIR/) { mkdir_all $dir . $name; }
	else { copy_to_all $dir . $name; }
	next;
    }
    if ($events =~ /MOVED_FROM/) {
	eval {
	    local $SIG{ALRM} = sub { die "alrm\n" };
	    $_ = '';
	    alarm 2;
	    $_ = <P>;
	    alarm 0;
	};
	# XXX in most cases ISDIR not handled, to implement fully would
	# XXX require examining fs trees in case read timeouts...
	# XXX only before copy_to it is checked so to avoid protocol breakage
	unless ($_) {
	#if ($ eq "alrm\n") {
	    remove_all $dir . $name;
	    next;
	}
	unless (/^\d+\s+\S*MOVED_TO/) {
	    remove_all $dir . $name;
	    redo; # note, continue block below not executed.
	}
	print 'iw: ', $_;
	my ($time2, $events2, $path2) = split ' ', $_, 3;
	my ($dir2, $name2) = split ' // ', $path2;
	chomp $name2;
	unless (chkexcludes $name2) {
	    remove_all $dir . $name;
	    next;
	}
	if ($time2 - $time > 1) { # heuristic :/
	    remove_all $dir . $name;
	    if ($events2 =~ /ISDIR/) { mkdir_all $dir2 . $name2; }
	    else { copy_to_all $dir2 . $name2; }
	    next;
	}
	move_all $dir . $name, $dir2 . $name2;
	next;
    }
} continue { $pevents = $events; }
