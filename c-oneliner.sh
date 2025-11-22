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
# Last modified: Sat 22 Nov 2025 16:13:33 +0200 too

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf  # hint: zsh -x thisfile [args] to trace execution

#LANG=C LC_ALL=C; export LANG LC_ALL

die () { printf %s\\n '' "$@" ''; exit 1; } >&2

verbose=false assy=false cppo=false opts=
xcmd=
while test $# -gt 0
do case $1
	in	-v)	verbose=true
	;;	-x)	xcmd=${2-}; shift
	;;	-E)	opts=$opts\ $1; cppo=true
	;;	-S)	opts=$opts\ $1; assy=true
	;;	-*)	opts=$opts\ $1
	;;	*)	break
   esac
   shift || die "$0: option '-x' requires an argument"
done

if test "$xcmd"
then
	bcmd=${xcmd%% *}
	bbcmd=`command -v "$bcmd"` || :
	test "$bbcmd" || die "'$bcmd': command not found"
	case $bbcmd in */*) ;; *) die "'$bbcmd': suspicions - no '/'s" ;; esac
	unset bcmd bbcmd
fi

if $verbose
then	x () { printf '+ %s\n' "$*" >&2; "$@"; }
else	x () { "$@"; }
fi

if test $# = 0
then
	exec >&2
	case $0 in /*) n=${0##*/} ;; *) n=$0 ;; esac
	echo
	echo Usage: $n "[-v] [-x 'cmd'] 'oneliner' [-opts...] [includes...]"
	echo
	echo "  -v:       verbose (show code & compilation)"
	printf "  -x 'cmd': the built executable is run using 'cmd'"
	echo " (e.g. strace)"
	echo
	echo "  More compiler options, starting with '-' may be given"
	echo
	printf '  With -E (preprocess only) or -S (assembler output),'
	echo " executable not built/run"; v=includes
	echo
	echo "  Some #$v are added based on the contents of the 'oneliner'".
	echo '  ".h"s appended to'" $v if not there (i.e. unistd -> unistd.h)".
	echo
	echo '  "-lm" is added to the linker options'
	echo
	echo '  Default compiler is "cc" - $CC can be used to change that'
	echo
	echo Example:; o=-std=c89
	echo "  CC='gcc' $n 'int i = pow(10, 4); printf(\"%d\", i)' math $o"
	echo
	#echo '  (pow() was not common enough for math.h to be auto-included.)'
	#echo
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

for arg
do
	case $arg
	in -E)	opts=$opts\ $arg; cppo=true
	;; -S)	opts=$opts\ $arg; assy=true
	;; -*)	opts=$opts\ $arg
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

if $cppo
then	x ${CC:-cc} $opts $tmp_oneliner_c
elif $assy
then
	x ${CC:-cc} $opts -o $tmp_oneliner $tmp_oneliner_c
	x cat $tmp_oneliner
else
	x ${CC:-cc} $opts -o $tmp_oneliner $tmp_oneliner_c -lm
	x $xcmd $tmp_oneliner "$@" # well, no args...
fi

echo
