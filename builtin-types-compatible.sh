#!/bin/sh

# SPDX-License-Identifier: Unlicense

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf  # hint: (z|ba|da|'')sh -x thisfile [args] to trace execution

die () { printf '%s\n' '' "$@" ''; exit 1; } >&2

test $# -gt 0 || die "Usage: ${0##*/} type [hdr [hdr...]] [cc options]" '' \
  'stdio[.h] and stdint[.h] are included, more hdr(s) may be needed...' \
  "first arg with leading '-' starts cc options, e.g. -D_LARGEFILE64_SOURCE" \
  '' ": try; $0 int"

case $1 in [a-zA-Z_]*) ;; *) die "'$1' does not start with [a-zA-Z] or '_'"
esac
case $1 in *[!a-zA-Z0-9_' ']*) die "'$1' contains chars outside [!a-zA-Z0-9_ ]"
esac

type=$1
shift
for a
do case $a in char|short|int|long)
		type=$type\ $a
		shift
	;; *) break
   esac
done


NL='
'
tbi=
for a
do case $a in -*) break
	;; *.h) tbi=${tbi:+$tbi$NL}"#include <$1>"
	;; *) tbi=${tbi:+$tbi$NL}"#include <$1.h>"
   esac
   shift
done

np=/tmp/butyco.$$
trap "set -x; rm -vf $np.c $np" 0
printf %s > $np.c "
#include <stdio.h>
#include <stdint.h>
$tbi
"'
#define TBI(o) "%18s (%lu): %d\n", \
	#o, sizeof(o), __builtin_types_compatible_p('"$type"', o)

int main(void)
{
	printf("%s, ", '"($type)"'-1 < 0? "signed": "unsigned");
	size_t s = sizeof('"$type"');
	printf("sizeof('"$type"'): %lu bytes, %lu bits\n", s, s << 3);
	printf(TBI(int8_t));
	printf(TBI(uint8_t));
	printf(TBI(int16_t));
	printf(TBI(uint16_t));
	printf(TBI(int32_t));
	printf(TBI(uint32_t));
	printf(TBI(int64_t));
	printf(TBI(uint64_t));
	printf(TBI(long long));
	printf(TBI(unsigned long long));
	printf(TBI(float));
	printf(TBI(double));
	printf(TBI(long double));
}
'
#cat $np.c
${CC:-gcc} "$@" -o $np $np.c
#ls -go $np
$np
# no traps after exec
exec rm $np.c $np
