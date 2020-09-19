#!/bin/sh
#
# $ custar.sh $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2020 Tomi Ollila
#	    All rights reserved
#
# Created: Wed 09 Sep 2020 20:00:17 EEST too
# Last modified: Sat 19 Sep 2020 15:19:22 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

# The external command GNU tar is licensed under GPL (mv(1), sh(1): lic.varies)

case ${BASH_VERSION-} in *.*) set -o posix; shopt -s xpg_echo; esac
case ${ZSH_VERSION-} in *.*) emulate ksh; esac

set -euf  # hint: sh -x thisfile [args] to trace execution

LANG=C LC_ALL=C; export LANG LC_ALL; unset LANGUAGE

TZ=UTC; export TZ

die () { echo; printf '%s\n' "$@"; echo; exit 1; } >&2

x () { printf '+ %s\n' "$*" >&2; "$@"; }
x_exec () { printf '+ %s\n' "$*" >&2; exec "$@"; die "exec '$*' failed"; }

test $# -ge 3 ||
	die "Usage: $0 tarname mtime [other-gtar-options] [--] files/dirs" '' \
		'  mtime formats (in UTC):' \
		'    yyyy-mm-dd  yyyy-mm-ddThh:mm:ss  yyyy-mm-dd+hh:mm:ss' \
		'    yyyy-mm-dd+hh:mm  yyyy-mm-dd+hh  hh:mm  d  @secs' \
		'  hh:mm -- hour and min today,  d -- number of days ago 00:00'


case $1 in ?*.tar) I=
	;; ?*.tgz | ?*.tar.gz) I='gzip --no-name'
	;; ?*.txz | ?*.tar.xz) I='xz'
	;; ?*.tlz | ?*.tar.lz) I='lzip'
	;; ?*.tbz2 | ?*.tar.bz2) I='bzip'
	;; *) die "Unknown file name suffix in '$1' (check $0 for known ones)"
esac

tarname=$1
mtime=$2

test -f "$2" ||
case $2 in 20[0-9][0-9]-[01][0-9]-[0-3][0-9]) # ok
	;; 20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[012][0-9]:[0-5][0-9]:[0-5][0-9])
		# the formats above accepted by gnu tar as is #
	;; 20[0-9][0-9]-[01][0-9]-[0-3][0-9]+[012][0-9]) # +hh -> Thh:00:00
		mtime=${2%+*}T${2##*+}:00:00
	;; 20[0-9][0-9]-[01][0-9]-[0-3][0-9]+[012][0-9]:[0-5][0-9]) # w/ mins
		mtime=${2%+*}T${2##*+}:00
	;; 20[0-9][0-9]-[01][0-9]-[0-3][0-9]+[012][0-9]:[0-5][0-9]:[0-5][0-9])
		mtime=${2%+*}T${2##*+}
	;; @[1-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) # secs since ep
		mtime=$2
	;; [012][0-9]:[0-5][0-9]|[0-9]:[0-5][0-9]) # hour:min today
		mtime=$2
	;; [0-9]) # number of days ago
		mtime="$2 days ago 00:00"
	;; *)  die "'$2': unknown (m)time format"
esac

shift 2

# note: gnu tar 1.28 or newer required

trap 'rm -f "$tarname".wip' 0

x tar --owner=root --group=root --format=ustar --sort=name \
	--mtime="$mtime" ${I:+-I "$I"} -cf "$tarname".wip "$@"

# note: no traps executed after exec
x_exec mv "$tarname".wip "$tarname"


# Local variables:
# mode: shell-script
# sh-basic-offset: 8
# tab-width: 8
# End:
# vi: set sw=8 ts=8
