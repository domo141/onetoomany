#if 0 /* -*- mode: c; c-file-style: "stroustrup"; tab-width: 8; -*-
 set -euf
 WARN="-Wall -Wextra -Wstrict-prototypes -Wformat=2" # -pedantic
 WARN="$WARN -Wcast-qual -Wpointer-arith" # -Wfloat-equal #-Werror
 WARN="$WARN -Wcast-align -Wwrite-strings -Wshadow" # -Wconversion
 WARN="$WARN -Waggregate-return -Wold-style-definition -Wredundant-decls"
 WARN="$WARN -Wbad-function-cast -Wnested-externs -Wmissing-include-dirs"
 WARN="$WARN -Wmissing-prototypes -Wmissing-declarations -Wlogical-op"
 WARN="$WARN -Woverlength-strings -Winline -Wundef -Wvla -Wpadded"
 case ${1-} in dbg) sfx=-dbg DEFS=-DDBG; shift ;; *) sfx= DEFS=-DDBG=0 ;; esac
 trg=${0##*''/}; trg=${trg%.c}$sfx.so; test -e "$trg" && rm "$trg"
 case ${1-} in '') set -- -O2; esac
 #case ${1-} in '') set -- -ggdb; esac
 x_exec () { printf %s\\n "$*" >&2; exec "$@"; }
 x_exec ${CC:-gcc} -std=c99 -shared -fPIC -o "$trg" "$0" $DEFS $@ -ldl
 exit not reached
 */
#endif
/*
 * $ ldpreload-mkdir-m777.c $
 *
 * Author: Tomi Ollila -- too ät iki piste fi
 *
 *      Copyright (c) 2023 Tomi Ollila
 *          All rights reserved
 *
 * Created: Sun 10 Dec 2023 18:34:50 EET too
 * Last modified: Mon 11 Dec 2023 22:34:00 +0200 too
 */

/* Create directories with mode 0777 (read/write/access permissions
 * to everyone, at the moment of creation.
 * Not the usual practise, but needed sometimes.
 *
 * This ld preload library wraps mkdir(2) and mkdirat(2) system calls
 * (when used via (libc) dynamic library), "hardcoding" 0777 as mode
 * parameter.
 * As usual, one must carefully test that the behavior is as
 * expected; This has been working when used with
 *     `LD_PRELOAD=path/to/ldpreload-mkdir-m777.so cp -r src dest`
 * (after `umask 000` as mkdir(2) behavior is modified by it). I haven't
 * tested cp -a --no-preserve=mode ..., but according to strace(2) output
 * it looks like those options make `cp` work a bit differently (at least
 * in a linux system) so it could be that this does not work with it.
 * As said, use cases to be tested for expected use.
 * (strace(1) is useful tool to be used for part of the testing; using it
 * told me that this wrapper is (also) useless for `mkdir -p a/b/c/d` ...)
 */

/* SPDX-License-Identifier: Unlicense */

#define _GNU_SOURCE /*needed for #define RTLD_NEXT ((void *) -1l) */
#include <fcntl.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>

#define null ((void*)0)

static void * dlsym_next(const char * symbol)
{
    void * sym = dlsym(RTLD_NEXT, symbol);
    char * str = dlerror();

    if (str != null) {
        fprintf(stderr, "finding symbol '%s' failed: %s", symbol, str);
        exit(1);
    }
    return sym;
}
#define set_next(name) *(void**)(&name##_next) = dlsym_next(#name)


int mkdir(const char * pathname, mode_t mode);
int mkdir(const char * pathname, mode_t mode)
{
    static int (*mkdir_next)(const char * pathname, mode_t mode) = null;
    if (! mkdir_next)
        set_next(mkdir);

    mode = 0777;
    return mkdir_next(pathname, mode);
}

int mkdirat(int dirfd, const char * pathname, mode_t mode);
int mkdirat(int dirfd, const char * pathname, mode_t mode)
{
    static int (*mkdirat_next)(int dirfd, const char * pathname, mode_t mode)
        = null;
    if (! mkdirat_next)
        set_next(mkdirat);

    mode = 0777;
    return mkdirat_next(dirfd, pathname, mode);
}
