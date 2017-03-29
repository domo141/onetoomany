#!/bin/dash
#!/bin/bash --posix
# $ gitrepos.sh $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2017 Tomi Ollila
#	    All rights reserved
#
# Created: Wed 01 Mar 2017 19:25:24 EET too
# Last modified: Wed 29 Mar 2017 22:03:46 +0300 too

# Some documentation at the end. License: 2-Clause (Simplified) BSD

: || {
#!perl
#line 18
=pod
}

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

# set -x
set -euf

umask 022

LANG=C LC_ALL=C; export LANG LC_ALL; unset LANGUAGE
PATH='/usr/bin:/bin'; export PATH

saved_IFS=$IFS; readonly saved_IFS

die () { printf '%s\n' "$*"; exit 1; } >&2

test "$#${1-}" = 2-c || {
	exec >&2
	echo Commands available:
	echo '  git-*    git ... '
	echo '  list     ssh ... list '
	echo '  mkrepo   ssh ... mkrepo [name]'
	echo '  rmrepo   ssh ... rmrepo (if empty)'
	echo '  ls       ssh ... ls [-flags]'
	echo '  rm       ssh ... rm [file]'
	echo '  cat      ssh ... cat [file]'
	echo '  scp      scp [-P port] ... '
	exit
}

#env >&2
#echo $# "$@" >&2

case $2 in *[!a-zA-Z0-9.,\ \'~/_-]*)
	die "$2: characters outside supported range (a-z A-Z 0-9 '.,~/_-)";
esac

IFS=" '"
set -- $2 ''
IFS=$saved_IFS

chkfilearg ()
{
	case $1 in */*) die "slashes ('/') not supported in path names"
		;; ..) die "unsuitable path name"
		;; '') die "pathname missing"
	esac
}

case ${1-}
in git-upload-pack | git-receive-pack | git-upload-archive )
	test $# = 3 || die "$1: argument count mismatch"
	p=$2
	case $p in ~*) p=${p#?}; esac
	case $p in /*) p=${p#?}; esac
	chkfilearg "$p"
	cd gitrepos || { mkdir gitrepos && cd gitrepos; }
	exec "$1" "$p"
	exit not reached

;; list)
	cd gitrepos || { mkdir gitrepos && cd gitrepos; }
	exec /bin/ls
	exit not reached

;; mkrepo)
	test $# = 3 || die "usage: $1 repository-name"
	chkfilearg "$2"
	cd gitrepos || { mkdir gitrepos && cd gitrepos; }
	case $2 in *.git) p=$2 ;; *) p=$2.git ;; esac
	/bin/mkdir "$p"
	trap "trap - 0; rm -rf '$p'" 0 INT HUP TERM
	( set -euf; cd "$p" && exec git init --quiet --bare )
	trap - 0 INT HUP TERM
	echo "Created repository '$2'".
	exit

;; rmrepo)
	test $# = 3 || die "usage: $1 repository-name"
	chkfilearg "$2"
	cd gitrepos || { mkdir gitrepos && cd gitrepos; }
	test -d "$2" || die "'$2': no such repository"
	test -d "$2/refs/heads" || die "unknown repository layout"
	contents=`exec ls "$2/refs/heads"`
	test "$contents" || exec /bin/rm -rf "$2"
	die "repository '$2' not empty"
;; ls)
	cd gitrepos-fs || { mkdir gitrepos-fs && cd gitrepos-fs; }
	unset LS_COLORS
	case $2 in -[^-]*) exec /bin/ls "$2" ;; *) exec /bin/ls ;; esac
	exit not reached
;; rm)
	test $# = 3 || die "usage: $1 filename"
	chkfilearg "$2"
	cd gitrepos-fs || { mkdir gitrepos-fs && cd gitrepos-fs; }
	exec /bin/rm -v "$2"
	exit not reached
;; cat)
	test $# = 3 || die "usage: $1 filename"
	chkfilearg "$2"
	cd gitrepos-fs || { mkdir gitrepos-fs && cd gitrepos-fs; }
	case `exec file "$2"` in *text*) ;; *)
		die "`exec file "$2"` -- not a text file"
	esac
	exec /bin/cat "$2"
	exit not reached
;; scp)
	case $2 in -f | -t ) ;; *) die "unsupported scp invocation" ;; esac
	chkfilearg "$3"
	cd gitrepos-fs || { mkdir gitrepos-fs && cd gitrepos-fs; }
	exec scp "$2" "$3"
	exit not reached
esac

# Uncomment to enable sftp (/sshfs!) support. The following fakechroot
# trick is used to avoid accidents from friendly & polite people, and
# may not protect against malicious intent.
#case ${1-}
#in /usr/lib*/sftp-server)
#	case $1 in */../*) exit 1; esac
#	cd gitrepos-fs || { mkdir gitrepos-fs && cd gitrepos-fs; }
#	FAKECHROOT_EXCLUDE_PATH=${1%/*}:/dev:/etc \
#	exec fakechroot /usr/bin/env /usr/sbin/chroot . "$1"
#	exit not reached
#esac

die "'$1': command not found"
exit not reached

=cut # perl helper to handle authorized_keys follows

use 5.8.1;
use strict;
use warnings;
use Digest::MD5 qw/md5_hex/;

die "Usage: $0 filename (ofilename | '.')\n" unless @ARGV == 2;
my $file = $ARGV[0];
my $ofil = $ARGV[1];
if ($ofil eq '.') {
	$ofil = $file;
	$ofil =~ s|.*/||;
}
die "'$file': does not end with '.pub'\n" unless $file =~ /[.]pub$/;
die "'$ofil': does not end with '.pub'\n" unless $ofil =~ /[.]pub$/;
die "'$ofil': contains unsupported characters\n" if $ofil =~ /[^\w.-]/;
die "'$file': no such file.\n" unless -f "$file";
die "'$file': unreadable.\n" unless -r "$file";

my $dir = $0; $dir =~ s|/[^/]+$|| or $dir = '.';

umask 022;

die "'$dir/.ssh': no such directory\n" unless -d "$dir/.ssh";
my $gitrepos_keydir = "$dir/.ssh/gitrepos-keys";
unless (-d $gitrepos_keydir) {
	system 'mkdir', $gitrepos_keydir;
	exit 1 if $?;
}
die "'$gitrepos_keydir': unwritable\n" unless -w "$gitrepos_keydir";
die "'$gitrepos_keydir/$ofil' exists\n" if -e "$gitrepos_keydir/$ofil";

my $authorized_keys = "$dir/.ssh/authorized_keys";
system 'touch', $authorized_keys unless -f $authorized_keys;
die "'$authorized_keys': unwritable\n" unless -w "$authorized_keys";

open O, '>', "$authorized_keys.new"
	or die "Cannot open '$authorized_keys.new' for writing: $!\n";

eval "END { unlink '$authorized_keys.new'; }";

system 'cp', $file, "$gitrepos_keydir/$ofil";
exit 1 if $?;

my %md5s;
print " md5...       file (leading content before keytype (if any) ignored)\n";
foreach (<$gitrepos_keydir/*.pub>) {
	my $ifile = $_;
	open I, '<', $ifile or die "Cannot open '$file'\n";
	my $line = <I>;
	unless ($line =~ /^(?:ssh|ecdsa)-/) {
		die "'$ifile' does not contain '(ssh|ecdsa)-*' (keytype) part\n"
			unless $line =~ s/^.*? (ssh|ecdsa)-/$1-/;
	}
	my $md5 = md5_hex($line);
	printf " %8.8s...  %s\n", $md5, $ifile;
	if (defined $md5s{$md5}) {
		print "File '$ifile' has the same md5 checksum\n";
		print "  as '$md5s{$md5}'. Skipping.\n";
		next;
	}
	$md5s{$md5} = $ifile;
	#print O 'restrict' -- not in older sshd's
	print O 'restrict,no-agent-forwarding,no-port-forwarding,no-pty';
	my $keyid = $ifile; $keyid =~ s|^.*/(.*).pub$|$1|;
	print O ',no-X11-forwarding,environment="', "KEYID=$keyid", '" ';
	print O $line;
	close I;
}
close O;
rename "$authorized_keys.new", $authorized_keys or
	die "Failed to write '$authorized_keys': $!\n";

__END__

# The purpose of this software is to provide environment where friendly
# and polite people can create and share code (via git repositories)
# and files (via scp (and possibly sftp/sshfs)). This system is something
# between git-shell(1) and gitolite (but with file storage); Provides some
# (restrictive) convenince but not much configurability.

# Create git(repos) user and set it up using the following commands:
#
#    sudo=sudo ;: one alternative: 'su' root shell and there sudo=
#    $sudo useradd -m -U -k /dev/null -s /home/git/gitrepos.sh git
#    $sudo cp gitrepos.sh ~git
#    $sudo chmod 555 ~git/gitrepos.sh
#    $sudo touch ~git/.hushlogin
#    $sudo mkdir -m 700 ~git/.ssh
#    $sudo chown git ~git/.ssh
#    $sudo perl -x ~git/gitrepos.sh ~/.ssh/id_rsa.pub username.pub
#    $sudo find ~git -ls
#
# Then execute `ssh git@host` to get command listing (other than git)...
#
# Keep adding more users with  $sudo perl -x ~git/gitrepos.sh ...
