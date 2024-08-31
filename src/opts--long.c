#if 0 /* -*- mode: c; c-file-style: "stroustrup"; tab-width: 8; -*-
 set -euf; trg=${0##*''/}; trg=${trg%.c}; test -e "$trg" && rm "$trg"
 test "${1-}" || set -- -O2
 #test "${1-}" || set -- -ggdb
 set -x; exec ${CC:-gcc -std=c11} "$@" -o "$trg" "$0"
 exit $?
 */
#endif
/*
 * $ opts--long.c -- sample code usable as a base for argument parsing $
 *
 * Author: Tomi Ollila -- too ät iki piste fi
 *
 *      Copyright (c) 2024 Tomi Ollila
 *          All rights reserved
 *
 * Created: Thu 29 Aug 2024 17:18:51 EEST too
 * Last modified: Sat 31 Aug 2024 18:06:30 +0300 too
 */

// (Ø) public domain, like https://creativecommons.org/publicdomain/zero/1.0/

#if defined(__linux__) && __linux__ || defined(__CYGWIN__) && __CYGWIN__
// on linux: man feature_test_macros -- try ftm.c at the end of it
#define _DEFAULT_SOURCE 1
// for older glibc's on linux (< 2.19 -- e.g. rhel7 uses 2.17...)
#define _BSD_SOURCE 1
#define _SVID_SOURCE 1
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#define _ATFILE_SOURCE 1
// more extensions (less portability?)
//#define _GNU_SOURCE 1
#endif

// hint: gcc -dM -E -xc /dev/null | grep -i gnuc
// also: clang -dM -E -xc /dev/null | grep -i gnuc
#if defined (__GNUC__) && defined (__STDC__)

//#define WERROR 1 // uncomment or enter -DWERROR on command line

#define DO_PRAGMA(x) _Pragma(#x)
#if defined (WERROR) && WERROR
#define PRAGMA_GCC_DIAG(w) DO_PRAGMA(GCC diagnostic error #w)
#else
#define PRAGMA_GCC_DIAG(w) DO_PRAGMA(GCC diagnostic warning #w)
#endif

#define PRAGMA_GCC_DIAG_E(w) DO_PRAGMA(GCC diagnostic error #w)
#define PRAGMA_GCC_DIAG_W(w) DO_PRAGMA(GCC diagnostic warning #w)
#define PRAGMA_GCC_DIAG_I(w) DO_PRAGMA(GCC diagnostic ignored #w)

#if 0 // use of -Wpadded gets complicated, 32 vs 64 bit systems
PRAGMA_GCC_DIAG_W (-Wpadded)
#endif

// to relax, change 'error' to 'warning' -- or even 'ignored'
// selectively. use #pragma GCC diagnostic push/pop to change the
// rules for a block of code in the source files including this.

PRAGMA_GCC_DIAG (-Wall)
PRAGMA_GCC_DIAG (-Wextra)

#if __GNUC__ >= 8 // impractically strict in gccs 5, 6 and 7
PRAGMA_GCC_DIAG (-Wpedantic)
#endif

#if __GNUC__ >= 7 || defined (__clang__) && __clang_major__ >= 12

// gcc manual says all kind of /* fall.*through */ regexp's work too
// but perhaps only when cpp does not filter comments out. thus...
#define FALL_THROUGH __attribute__ ((fallthrough))
#else
#define FALL_THROUGH ((void)0)
#endif

#ifndef __cplusplus
PRAGMA_GCC_DIAG (-Wstrict-prototypes)
PRAGMA_GCC_DIAG (-Wbad-function-cast)
PRAGMA_GCC_DIAG (-Wold-style-definition)
PRAGMA_GCC_DIAG (-Wmissing-prototypes)
PRAGMA_GCC_DIAG (-Wnested-externs)
#endif

// -Wformat=2 ¡currently! (2020-11-11) equivalent of the following 4
PRAGMA_GCC_DIAG (-Wformat)
PRAGMA_GCC_DIAG (-Wformat-nonliteral)
PRAGMA_GCC_DIAG (-Wformat-security)
PRAGMA_GCC_DIAG (-Wformat-y2k)

PRAGMA_GCC_DIAG (-Winit-self)
PRAGMA_GCC_DIAG (-Wcast-align)
PRAGMA_GCC_DIAG (-Wpointer-arith)
PRAGMA_GCC_DIAG (-Wwrite-strings)
PRAGMA_GCC_DIAG (-Wcast-qual)
PRAGMA_GCC_DIAG (-Wshadow)
PRAGMA_GCC_DIAG (-Wmissing-include-dirs)
PRAGMA_GCC_DIAG (-Wundef)

#ifndef __clang__ // XXX revisit -- tried with clang 3.8.0
PRAGMA_GCC_DIAG (-Wlogical-op)
#endif

#ifndef __cplusplus // supported by c++ compiler but perhaps not worth having
PRAGMA_GCC_DIAG (-Waggregate-return)
#endif

PRAGMA_GCC_DIAG (-Wmissing-declarations)
PRAGMA_GCC_DIAG (-Wredundant-decls)
PRAGMA_GCC_DIAG (-Winline)
PRAGMA_GCC_DIAG (-Wvla)
PRAGMA_GCC_DIAG (-Woverlength-strings)
PRAGMA_GCC_DIAG (-Wuninitialized)

//PRAGMA_GCC_DIAG (-Wfloat-equal)
//PRAGMA_GCC_DIAG (-Wconversion)

// avoiding known problems (turning some errors set above to warnings)...
#if __GNUC__ == 4
#ifndef __clang__
PRAGMA_GCC_DIAG_W (-Winline) // gcc 4.4.6 ...
PRAGMA_GCC_DIAG_W (-Wuninitialized) // gcc 4.4.6, 4.8.5 ...
#endif
#endif

#undef PRAGMA_GCC_DIAG_I
#undef PRAGMA_GCC_DIAG_W
#undef PRAGMA_GCC_DIAG_E
#undef PRAGMA_GCC_DIAG
#undef DO_PRAGMA

#endif /* defined (__GNUC__) && defined (__STDC__) */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <err.h>

static const char * optarg_(const char * optp, const char *** argvp)
{
    if ((++optp)[0] != 0) return optp;
    const char * ov = (++(*argvp))[0];
    if (ov == NULL) errx(1, "option requires an argument -- '%c'", optp[-1]);
    return ov;
}

static const char * longoptarg(const char * optend, const char *** argvp)
{
    if (*optend == '=') return optend + 1;
    if (*optend != 0) return 0;

    const char * ov = (++(*argvp))[0];
    if (ov == NULL) errx(1, "option '%s' requires an argument", argvp[0][-1]);
    return ov;
}

#define IF_LONGOPT(o) if (memcmp(arg + 2, "" o, sizeof(o)) == 0)

#define LONGOPTARG(v, o) \
    if (memcmp(arg + 2, "" o, sizeof(o) - 1) == 0) { \
    const char * ov = longoptarg(arg + 1 + sizeof(o), &argv); \
    if (ov) { v = ov; continue; }} ((void)0)

int main(int argc, const char * argv[])
{
    const char ** prognamep = argv++;
    if (argc < 2) {
        fprintf(
            stderr, "\n"
            "Usage: %s [opts] [(-opts|--opts)...] [--] rest-args\n\n"
            "opts--long sample (POSIXLY_CORRECTish way), "
            "mimicking some GNU tar(1) options:\n"
            "  -c, -C DIR, -f FILE, -T FILES-FROM\n"
            "  --create, --directory=DIR, --file=FILE, --files-from=FILE\n"
            "  --totals[=SIGNAL] (i.e. optional argument, need = for arg)\n"
            "and one \"special case\" (not in tar), -NUMBER\n"
            "First (opt)arg may lack leading '-' "
            "(like GNU tar) (removable hack)\n"
            "Single '-' considered non-option; no options after nonoption\n"
            "License: Unlicense\n\n", *prognamep);
        exit(0);
    }
    char opt_create = 0;
    int opt_number = -1;
    const char * opt_file = NULL;
    const char * opt_ffrm = NULL;
    const char * opt_chdir = NULL;
    const char * opt_totals = NULL;

    for (const char * arg = argv[0]; arg; arg = (++argv)[0]) {
        if (arg[0] != '-') {
#if 0
            break;
#else
            if (argv - 1 != prognamep) break;
            // hack to support trad. tar(1) feature...
            arg--;
#endif
        }
        if (arg[1] == 0) break;
        if (arg[1] == '-') {
            if (arg[2] == '\0') { argv++; break; }
            IF_LONGOPT("create") { opt_create = 1; continue; }
            IF_LONGOPT("totals") { opt_totals = "yes"; continue; }
            LONGOPTARG(opt_file, "file");
            LONGOPTARG(opt_ffrm, "files-from");
            LONGOPTARG(opt_chdir, "directory");
            LONGOPTARG(opt_totals, "totals");
            errx(1, "unrecognized option '%s'", arg);
        }
        if (arg[1] >= '0' && arg[1] <= '9') {
            opt_number = atoi(arg + 1);
            continue;
        }
        for (int c, i = 1; (c = arg[i]) != 0; i++) {
            switch (c) {
            case 'c': opt_create = 1; continue;
            case 'f': opt_file = optarg_(arg + i, &argv); break;
            case 'T': opt_ffrm = optarg_(arg + i, &argv); break;
            case 'C': opt_chdir = optarg_(arg + i, &argv); break;
            default:
                errx(1, "invalid option -- '%c'", c);
            }
            break;
        }
    }
    printf("create: %d\nfile: %s\nfiles from: %s\n"
           "directory: %s\ntotals: %s\nnumber: %d\n",
           opt_create, opt_file, opt_ffrm, opt_chdir, opt_totals, opt_number);
    printf("args left: %d\n", argc - (int)(argv - prognamep));
    while (argv[0]) printf("arg: %s\n", argv++[0]);
    return 0;
}
