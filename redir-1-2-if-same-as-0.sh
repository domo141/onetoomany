#!/bin/sh
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2024 Tomi Ollila
#	    All rights reserved
#
# Created: Mon 03 Dec 2024 18:31:39 EET too
# Last modified: Wed 18 Dec 2024 23:29:28 +0200 too
#
# Ideas from:
# https://stackoverflow.com/questions/593724/
# redirect-stderr-stdout-of-a-process-after-its-been-started-using-command-lin/
# 3834605#3834605

set -euf

die () { printf '%s\n' '' "$@" ''; exit 1; } >&2

test $# = 2 || test $# = 1 || die "Usage: ${0##*/} {pid} [file|'!']" "\

Redirect stdout and stderr to 'file' if both of those are same as stdin.
The 'sameness' is required in this script so that those can later be
restored with the '!' option.
The restore option '!' cannot do similar checks as the other usage, so
better check first by running with one arg: ${0##*/} {pid}
: Try it; $0 \$\$"

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

printf gcc:\ ; command -v gcc || die "'gcc': command not found (but see $0)"

# gcc is needed to get value of O_RDWR|O_CREAT|O_APPEND, if gcc did not exist,
# one could use e.g. the perl(1)/python(1) oneliners instead (see below),
# or any other tool that can be used to determine the values of
# O_RDWR, O_CREAT and O_APPEND (or guess all linux resolve to '1090' (0x442)...
# as this most probably work on modern linuxes only...)

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

# perl -le 'use POSIX; print O_RDWR|O_CREAT|O_APPEND' ;: or
# python -c 'import os; print(os.O_RDWR|os.O_CREAT|os.O_APPEND)'
# would do, but if gdb is installed, gcc is more likely, too...
# -- ok, some text-file-busys w/ later kernel
# -- and tmpfs could be noexec, so outcommenting...
#td=`mktemp`
#exec 9<>$td || { unlink $td; exit 1; }
#unlink $td
#unset td

#printf %s\\n '#include <fcntl.h>' '#include <stdio.h>' 'int main(void) {' \
#	'printf("%d", O_RDWR|O_CREAT|O_APPEND); return 0; }' \
#	| gcc -pipe -xc -o /dev/fd/9 -
#ls -l /dev/fd/9
#rwca=`ld.so /dev/fd/9`
#exec 9>&-
# ... and
rwca=`perl -le 'use POSIX; print O_RDWR|O_CREAT|O_APPEND'`
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
