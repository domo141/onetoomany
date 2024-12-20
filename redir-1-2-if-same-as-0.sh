#!/bin/sh
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2024 Tomi Ollila
#	    All rights reserved
#
# Created: Mon 03 Dec 2024 18:31:39 EET too
# Last modified: Fri 20 Dec 2024 20:52:15 +0200 too
#
# Ideas from:
# https://stackoverflow.com/questions/593724/
# redirect-stderr-stdout-of-a-process-after-its-been-started-using-command-lin/
# 3834605#3834605
#
# SPDX-License-Identifier: BSD-2-Clause

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf

die () { printf '%s\n' '' "$@" ''; exit 1; } >&2

test $# = 2 || test $# = 1 || die "Usage: ${0##*/} {pid} [file|'!']" "\

Redirect stdout and stderr of a running process to 'file' if both of those
are same as stdin. The 'sameness' is required in this script so that those
can later be restored with the '!' option.
The restore option '!' cannot do similar checks as the other usage, so
better check first by running with one arg: ${0##*/} {pid}

: Try it; $0 \$\$

gdb(1) is used to attach to the process to do the redirections."

case $1 in '') die "Arg 1 (pid) empty"
	;; *[!0-9]*) die "Non-digit chars in '$1'"
esac

if test $# = 1
then
	printf cmd:\ ; tr \\0 ' ' < /proc/$1/cmdline; echo
	exec /bin/ls -l /proc/$1/fd/0 /proc/$1/fd/1 /proc/$1/fd/2
	exit not reached
fi

printf gdb:\ ; command -v gdb || die "'gdb': command not found"

if test "$2" = '!' # restore by dub2ing fd 0 to 1 and 2
then
	td=`mktemp`
	exec 9<>$td || { unlink $td; exit 1; }
	unlink $td
	unset td
	printf %s\\n >&9 'set scheduler-locking on' \
		'call (int)dup2(0, 1)' 'call (int)dup2(0, 2)' q
	cat /dev/fd/9
	exec gdb -p $1 -batch -x /dev/fd/9 </dev/null
	exit not reached
fi
# else #

test /proc/$1/fd/0 -ef /proc/$1/fd/1 || {
	p=/proc/$1/fd
	die "stdin: '`readlink $p/0`' not same as stdout: '`readlink $p/1`'"
}
test /proc/$1/fd/0 -ef /proc/$1/fd/2 || {
	p=/proc/$1/fd
	die "stdin: '`readlink $p/0`' not same as stderr: '`readlink $p/2`'"
}

fn=`realpath "$2"`
case $fn in *'"'*) die "'\"'s in '$fn'"
esac

test -e "$fn" && test ! -f "$fn" && die "'$fn' exists but is not a file"
# ensure that /path/ there exists
: >> "$fn"

# at first, gcc(1) was used to build program to get the value of
# O_RDWR | O_CREAT | O_APPEND, but then, "complexity" arrived where
# to, and how to write that temporary prog (text file busy/noexec fs)
# so:
if command -v perl >/dev/null
then
	rwca=`perl -le 'use POSIX; print O_RDWR|O_CREAT|O_APPEND'`
elif command -v python3 >/dev/null
then
	rwca=`python3 -c 'import os; print(os.O_RDWR|os.O_CREAT|os.O_APPEND)'`
else
	die "Neither perl(1) nor python3(1) command found"
fi
#echo $rwca

td=`mktemp`
exec 9<>$td || { unlink $td; exit 1; }
unlink $td
unset td

fd='$fd'
echo >&9 "
set scheduler-locking on
set $fd=(int)open(\"$fn\", $rwca)
call (int)dup2($fd, 1)
call (int)close($fd)
call (int)dup2(1, 2)
q
"
cat /dev/fd/9
exec \
gdb -p $1 -batch -x /dev/fd/9 </dev/null
