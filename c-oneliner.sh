#!/bin/sh
# -*- mode: shell-script; sh-basic-offset: 8; tab-width: 8 -*-
# $ c-oneliner.sh $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2015 Tomi Ollila
#	    All rights reserved
#
# Created: between 2001 and 2006 too...
# Last modified: Mon 19 May 2025 22:50:51 +0300 too

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf  # hint: zsh -x thisfile [args] to trace execution

#LANG=C LC_ALL=C; export LANG LC_ALL

die () { printf %s\\n '' "$@" ''; exit 1; } >&2

verbose=false assy=false
while test $# -gt 0
do case $1
	in	-v|-x)	verbose=true
	;;	-a)	assy=true
	;;	-*)	die "'$1': unknown option"
	;;	*)	break
   esac
   shift
done

case ${1-} in strace | ltrace ) pfxcmd=$1; shift
	;; *) pfxcmd=
esac

if $verbose
then	x () { printf '+ %s\n' "$*" >&2; "$@"; }
else	x () { "$@"; }
fi

if test $# = 0
then
	exec >&2
	case $0 in /*) cn=${0##*/} ;; *) cn=$0 ;; esac
	echo
	echo Usage: $cn "[-v] [-a] [[sl]trace] 'oneliner' [-opts] [includes...]"
	echo
	echo "  '-v': verbose (show code & compilation), '-a': assembler dump".
	echo
	echo "  'strace': the built executable is run using strace(1)".
	echo "  'ltrace': the built executable is run using ltrace(1)".
	echo
	echo '  "-lm" is added to the linker options.'; v='#includes'
	echo
	echo "  More compiler options, starting with '-' may be given."
	echo
	echo "  Some $v are added based on the contents of the 'oneliner'".
	echo '  ".h"s appended to'" $v if not there (i.e. string -> string.h)".
	echo
	echo '  Default compiler is "gcc". $CC can be used to change that'.
	echo
	echo Example:; v='gcc -std=c89'
	echo "  CC='$v' $cn 'int i = pow(10, 4); printf(\"%d\", i)' math"
	echo
	echo '  (pow() was not common enough for math.h to be auto-included.)'
	echo
	exit 1
fi

umask 077
tmp_oneliner_d=`mktemp -d`
trap "rm -rf $tmp_oneliner_d" 0 INT HUP TERM

tmp_oneliner=$tmp_oneliner_d/oneliner
tmp_oneliner_c=$tmp_oneliner.c

exec 3>&1 1>$tmp_oneliner_c

iis=' '

# add include if not added already
addi ()
{
	case $iis in *' '$1' '*) return 0; esac
	iis=$iis$1' '
	echo "#include <$1>"
}

ol=$1
shift

opts=

for arg
do
	case $1 in -*)  opts=$opts\ $arg
		;; *.h) addi "$arg"
		;; *)	addi "$arg.h"
	esac
done

case $ol in *printf*) addi 'stdio.h'
esac
case $ol in *strlen*) addi 'string.h'
esac
#case $1 in **) addi ''
#esac

case $ol in *'}' | *';' ) ;; *) ol="$ol;" ;; esac

#echo 'int main(int argc, char ** argv)' \
printf %s\\n \
	'int main(void)' '{' \
	"  $ol" \
	'  return 0;' \
	'}'

exec 1>&3 3>&-

if $verbose
then x cat $tmp_oneliner_c
fi

if $assy
then
	x ${CC:-gcc} $opts -S -o $tmp_oneliner $tmp_oneliner_c
	x cat $tmp_oneliner
else
	x ${CC:-gcc} $opts -o $tmp_oneliner $tmp_oneliner_c -lm
	x $pfxcmd $tmp_oneliner "$@" # well, no args...
fi

echo
