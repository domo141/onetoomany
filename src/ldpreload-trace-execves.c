#if 0 /* -*- mode: c; c-file-style: "stroustrup"; tab-width: 8; -*-
 set -euf
 case ${1-} in dbg) sfx=-dbg DEFS=-DDBG; shift ;; *) sfx= DEFS=-DDBG=0 ;; esac
 trg=${0##*''/}; trg=${trg%.c}$sfx.so; test -e "$trg" && rm "$trg"
 test $# = 0 && set -- -O2
 #test $# = 0 && set -- -ggdb
 x_exec () { printf %s\\n "$*" >&2; exec "$@"; }
 x_exec ${CC:-gcc} -std=c99 -shared -fPIC -o "$trg" "$0" $DEFS $@ -ldl
 exit $?
 */
#endif
/*
 * $ ldpreload-trace-execves.c $
 *
 * Attempt to trace library functions that eventually lead to call execve(2)
 *
 * Author: Tomi Ollila -- too ät iki piste fi
 *
 * SPDX-License-Identifier: Unlicense
 *
 * Created: Sat 27 Jun 2026 11:36:29 +0300 too
 * Last modified: Sun 28 Jun 2026 13:44:21 +0300 too
 */
/* Execute  sh ldpreload-trace-execves.c  to compile
 */
/* Try as (e.g.)
 *  $ LD_PRELOAD=$PWD/ldpreload-trace-execves.so env /bin/true
 *  $ perl -x ldpreload-trace-execves.c
 *  $ LD_PRELOAD=$PWD/ldpreload-trace-execves.so gdb --args gcc -xc -c /dev/null
 */
/*
 * Probably most useful as a starting point to mangle exec* calls.
 * Note that there may be more library functions that finally call execve().
 * LD_PRELOAD=$PWD/ldpreload-trace-execves.so strace -f -ooo -e trace=execve ...
 */

// -- set compiler warnings -- //
// hint: gcc -dM -E -xc /dev/null | grep -i gnuc
// also: clang -dM -E -xc /dev/null | grep -i gnuc
#if defined (__GNUC__) && defined (__STDC__)

//#define WERROR 1 // uncomment or enter -DWERROR on command line/the includer

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

#if __GNUC__ >= 8 // impractically strict in gccs 5, 6 and 7 :fixme clang_major
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
//
PRAGMA_GCC_DIAG (-Wformat-signedness)

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
// -- end set compiler warnings -- //

#define _GNU_SOURCE /* needed for #define RTLD_NEXT ((void *) -1l) */

// sometimes one may need to "hid" original prototypes to get code compiled
// then it is very important to ensure the types are compatible enough...

//#define execve execve_hidden
//#define execvpe execvpe_hidden
//#define execvp execvp_hidden
//#define execv execv_hidden

//#define execl execl_hidden
//#define execlp execlp_hidden
//#define execle execle_hidden

#define posix_spawn posix_spawn_hidden
#define posix_spawnp posix_spawnp_hidden

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <spawn.h>
#include <dlfcn.h>

#undef posix_spawnp
#undef posix_spawn

#undef execle
#undef execlp
#undef execl

#undef execv
#undef execvp
#undef execvpe
#undef execve

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


// Macros FTW! -- use gcc -E to examine expansion

#define _deffn(_rt, _fn, _args) \
_rt _fn _args; \
_rt _fn _args { \
    static _rt (*_fn##_next) _args = null; \
    if (! _fn##_next ) *(void**) (&_fn##_next) = dlsym_next(#_fn);

#if 1 || DBG
#define cprintf(...) fprintf(stderr, __VA_ARGS__)
#else
#define cprintf(...) do {} while (0)
#endif

#define VP (void*)

// note: the 'const's in original funcs not here....

// note: not marking argv nor envp char *const ... //
_deffn ( int, execve, (const char * pathname, char * argv[], char * envp[]) )
#if 0
{
#endif
    cprintf("*** execve(\"%s\", %p, %p)\n", pathname, VP argv, VP envp);
    return execve_next(pathname, argv, envp);
}

_deffn ( int, execvpe, (const char * file, char * argv[], char * envp[]) )
#if 0
{
#endif
    cprintf("*** execvpe(\"%s\", %p, %p)\n", file, VP argv, VP envp);
    return execvpe_next(file, argv, envp);
}

_deffn ( int, execvp, (const char * file, char * argv[]) )
#if 0
{
#endif
    cprintf("*** execvp(\"%s\", %p)\n", file, VP argv);
    return execvp_next(file, argv);
}

_deffn ( int, execv, (const char * pathname, char * argv[]) )
#if 0
{
#endif
    cprintf("*** execv(\"%s\", %p)\n", pathname, VP argv);
    return execv_next(pathname, argv);
}

static inline int countargs(char * arg, va_list ap)
{
    int i;
    for (i = 1; arg; i++) {
	arg = va_arg(ap, char *);
    }
    //cprintf("-- count: %d\n", i);
    return i;
}
static inline char ** mkargv(int c, char * arg, va_list ap)
{
    char ** av = (char **)malloc(c * sizeof (char **));
    if (av == null) exit(11);
    int i;
    for (i = 0; arg; i++) {
	av[i] = arg;
	arg = va_arg(ap, char *);
    }
    av[i] = null;
    //cprintf("-- mk_ix: %d\n", i);
    return av;
}

#define _deffn2(_rt, _fn, _args, _rt2, _fn2, _args2) \
_rt _fn _args; \
_rt _fn _args { \
    static _rt2 (*_fn2##_next) _args2 = null; \
    if (! _fn2##_next ) *(void**) (&_fn2##_next) = dlsym_next(#_fn2);


_deffn2 ( int, execl, (const char * pathname, char * arg, ...),
	  int, execv, (const char *, char **) )
#if 0
{
#endif
    cprintf("*** execl(\"%s\", \"%s\"...)\n", pathname, arg);
    va_list ap;
    va_start(ap, arg);
    int c = countargs(arg, ap);
    va_end(ap);
    va_start(ap, arg);
    char ** av = mkargv(c, arg, ap);
    va_end(ap);

    return execv_next(pathname, av);
}

_deffn2 ( int, execlp, (const char * pathname, char * arg, ...),
	  int, execvp, (const char *, char **) )
#if 0
{
#endif
    cprintf("*** execlp(\"%s\", \"%s\"...)\n", pathname, arg);
    va_list ap;
    va_start(ap, arg);
    int c = countargs(arg, ap);
    va_end(ap);
    va_start(ap, arg);
    char ** av = mkargv(c, arg, ap);
    va_end(ap);

    return execvp_next(pathname, av);
}

_deffn2 ( int, execle, (const char * pathname, char * arg, ...),
	  int, execve, (const char *, char **, char **) )
#if 0
{
#endif
    cprintf("*** execle(\"%s\", \"%s\"...)\n", pathname, arg);
    va_list ap;
    va_start(ap, arg);
    int c = countargs(arg, ap);
    va_end(ap);
    va_start(ap, arg);
    char ** argv = mkargv(c, arg, ap);
    char ** envp = va_arg(ap, char **);
    va_end(ap);

    return execve_next(pathname, argv, envp);
}

// posix_spawn...

_deffn ( int, posix_spawn,
	 (pid_t *restrict  pid, const char *restrict path,
	  const posix_spawn_file_actions_t *restrict file_actions,
	  const posix_spawnattr_t *restrict attrp,
	  char * argv[], char * envp[]) )
#if 0
{
#endif
    cprintf("*** posix_spawn(\"%s\", %p %p)\n", path, VP argv, VP envp);
    return posix_spawn_next(pid, path, file_actions, attrp, argv, envp);
}

_deffn ( int, posix_spawnp,
	 (pid_t *restrict pid, const char *restrict file,
	  const posix_spawn_file_actions_t *restrict file_actions,
	  const posix_spawnattr_t *restrict attrp,
	  char * argv[], char * envp[]) )
#if 0
{
#endif
    cprintf("*** posix_spawnp(\"%s\", %p %p)\n", file, VP argv, VP envp);
    return posix_spawnp_next(pid, file, file_actions, attrp, argv, envp);
}


/* run test code for the execl* functions - perl -x ldpreload-trace-execves.c

#!perl
#line 302
#'''' 302

$ENV{LD_PRELOAD} = './ldpreload-trace-execves.so';
$" = ', ';
sub c($@) {
    my $t = shift;
    unlink 'a.out';
    open P, '|-', qw/gcc -std=gnu99 -xc -/;
    print P "#include <unistd.h>\nextern char **environ;\n",
	    "int main(void) {\n\t",
	    qq'$t("/bin/echo", "echo", "$t:", @_);\n}\n';
    close P;
    system qw'./a.out'
}

c 'execl', '"1"', '"2"', '"3"', 'NULL';
c 'execlp', '"1"', '"2"', '"3"', 'NULL';
c 'execle', '"1"', '"2"', '"3"', 'NULL', 'environ';
exec qw'strace -e trace=execve ./a.out';
*/
