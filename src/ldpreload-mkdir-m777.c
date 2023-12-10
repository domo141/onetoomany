#if 0 /* -*- mode: c; c-file-style: "stroustrup"; tab-width: 8; -*-
 set -euf; uname=`uname`
 WARN="-Wall -Wextra -Wstrict-prototypes -Wformat=2" # -pedantic
 WARN="$WARN -Wcast-qual -Wpointer-arith" # -Wfloat-equal #-Werror
 WARN="$WARN -Wcast-align -Wwrite-strings -Wshadow" # -Wconversion
 WARN="$WARN -Waggregate-return -Wold-style-definition -Wredundant-decls"
 WARN="$WARN -Wbad-function-cast -Wnested-externs -Wmissing-include-dirs"
 WARN="$WARN -Wmissing-prototypes -Wmissing-declarations -Wlogical-op"
 WARN="$WARN -Woverlength-strings -Winline -Wundef -Wvla -Wpadded"
 case ${1-} in dbg) sfx=-dbg DEFS=-DDBG; shift ;; *) sfx= DEFS=-DDBG=0 ;; esac
 trg=${0##*''/}; trg=${trg%.c}$sfx.so; test ! -e "$trg" || rm "$trg"
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
 * Last modified: Sun 10 Dec 2023 18:48:59 +0200 too
 */

/* Sometimes there is need all directories with mode 777...
 * umask 0; mkdir -p a/b/c/d ;: will create all dirs with mode
 * 0777    -- and this wrapper makes no difference there.
 * OTOH, cp(1) -r does not have option to set permissions
 * (uses (e.g.) 0755 for directories...)
 * LD_PRELOAD=path/to/ldpreload-mkdir-m777.so cp -r src dest
 * (usually) makes the created directories with 0777 as mode).
 */

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
