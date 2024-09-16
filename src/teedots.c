#if 0 /* -*- mode: c; c-file-style: "stroustrup"; tab-width: 8; -*-
 set -euf; trg=${0##*''/}; trg=${trg%.c}; test ! -e "$trg" || rm "$trg"
 case ${1-} in '') set x -O2; shift; esac
 #case ${1-} in '') set x -ggdb; shift; esac
 set -x; exec ${CC:-gcc} -std=c99 "$@" -o "$trg" "$0"
 exit $?
 */
#endif
/*
 * $ teedots.c $
 *
 * Author: Tomi Ollila -- too ät iki piste fi
 *
 *      Copyright (c) 2022 Tomi Ollila
 *          All rights reserved
 *
 * Created: Thu 27 Oct 2022 19:46:35 EEST too
 * Last modified: Mon 16 Sep 2024 19:34:21 +0300 too
 */

/* how to try: sh thisfile.c -DTEST, then ./thisfile logf cat thisfile.c */

/* SPDX-License-Identifier: BSD-2-Clause */

// hint: gcc -dM -E -xc /dev/null | grep -i gnuc
// also: clang -dM -E -xc /dev/null | grep -i gnuc
#if defined (__GNUC__)

#if 0 // use of -Wpadded gets complicated, 32 vs 64 bit systems
#pragma GCC diagnostic warning "-Wpadded"
#endif

// to relax, change 'error' to 'warning' -- or even 'ignored'
// selectively. use #pragma GCC diagnostic push/pop to change
// the rules temporarily

#pragma GCC diagnostic error "-Wall"
#pragma GCC diagnostic error "-Wextra"

#if __GNUC__ >= 8 // impractically strict in gccs 5, 6 and 7
#pragma GCC diagnostic error "-Wpedantic"
#endif

#if __GNUC__ >= 7 || defined (__clang__) && __clang_major__ >= 12

// gcc manual says all kind of /* fall.*through */ regexp's work too
// but perhaps only when cpp does not filter comments out. thus...
#define FALL_THROUGH __attribute__ ((fallthrough))
#else
#define FALL_THROUGH ((void)0)
#endif

#ifndef __cplusplus
#pragma GCC diagnostic error "-Wstrict-prototypes"
#pragma GCC diagnostic error "-Wbad-function-cast"
#pragma GCC diagnostic error "-Wold-style-definition"
#pragma GCC diagnostic error "-Wmissing-prototypes"
#pragma GCC diagnostic error "-Wnested-externs"
#endif

// -Wformat=2 ¡currently! (2020-11-11) equivalent of the following 4
#pragma GCC diagnostic error "-Wformat"
#pragma GCC diagnostic error "-Wformat-nonliteral"
#pragma GCC diagnostic error "-Wformat-security"
#pragma GCC diagnostic error "-Wformat-y2k"

#pragma GCC diagnostic error "-Winit-self"
#pragma GCC diagnostic error "-Wcast-align"
#pragma GCC diagnostic error "-Wpointer-arith"
#pragma GCC diagnostic error "-Wwrite-strings"
#pragma GCC diagnostic error "-Wcast-qual"
#pragma GCC diagnostic error "-Wshadow"
#pragma GCC diagnostic error "-Wmissing-include-dirs"
#pragma GCC diagnostic error "-Wundef"

#ifndef __clang__ // XXX revisit -- tried with clang 3.8.0
#pragma GCC diagnostic error "-Wlogical-op"
#endif

#ifndef __cplusplus // supported by c++ compiler but perhaps not worth having
#pragma GCC diagnostic error "-Waggregate-return"
#endif

#pragma GCC diagnostic error "-Wmissing-declarations"
#pragma GCC diagnostic error "-Wredundant-decls"
#pragma GCC diagnostic error "-Winline"
#pragma GCC diagnostic error "-Wvla"
#pragma GCC diagnostic error "-Woverlength-strings"
#pragma GCC diagnostic error "-Wuninitialized"

//ragma GCC diagnostic error "-Wfloat-equal"
//ragma GCC diagnostic error "-Werror"
//ragma GCC diagnostic error "-Wconversion"

// avoiding known problems (turning some errors set above to warnings)...
#if __GNUC__ == 4
#ifndef __clang__
#pragma GCC diagnostic warning "-Winline" // gcc 4.4.6 ...
#pragma GCC diagnostic warning "-Wuninitialized" // gcc 4.4.6, 4.8.5 ...
#endif
#endif

#endif /* defined (__GNUC__) */

// something needed with glibc headers...
#define _DEFAULT_SOURCE // glibc >= 2.19
#define _POSIX_C_SOURCE 200112L // for getaddrinfo() when glibc < 2.19
#define _BSD_SOURCE // for SA_RESTART when glibc < 2.19

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/uio.h>
#include <time.h>
#include <err.h>

/* some compiler setups complain:  warning: ignoring return value of ‘write’,
   declared with attribute warn_unused_result [-Wunused-result] */
#define write (void)!write

int ffd = -1;

static void tsmsgf(const char * fmt, ...) /* add __attribute__((...))) */
{
    struct timespec tv;
    clock_gettime(CLOCK_REALTIME, &tv);
    struct tm * tm = localtime(&tv.tv_sec);
    char buf[256];
    int l = snprintf(buf, sizeof buf, "%d-%02d-%02d %02d:%02d:%02d,%09ld: ",
                     tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday,
                     tm->tm_hour, tm->tm_min, tm->tm_sec, tv.tv_nsec);
    va_list ap;
    va_start(ap, fmt);
    l = l + vsnprintf(buf + l, sizeof buf - l, fmt, ap);
    va_end(ap);
    if (l >= (int)sizeof buf) l = (int)sizeof buf - 1;
    write(ffd, buf, l);
    write(1, buf, l);
}

#define edie(...) err(1, __VA_ARGS__)

static pid_t cpid = -1;
static void run_command(char * cmdl[])
{
    int pipefd[2];
    if (pipe(pipefd) < 0) edie("pipe");
    pid_t pid = fork();
    if (pid < 0) edie("fork");
    if (pid > 0) {
        /* parent */
        close(pipefd[1]);
        dup2(pipefd[0], 0);
        close(pipefd[0]);
        cpid = pid;
        return;
    }
    /* child */
    close(pipefd[0]);
    dup2(pipefd[1], 1);
    dup2(1, 2);
    close(pipefd[1]);
    execvp(cmdl[0], cmdl);
    edie("execve %s ...", cmdl[0]);
}

#ifndef TEST
#define TEST 0
#endif

#if TEST
#if TEST & 1
static size_t rndsiz(void) { return 7; }
#else
static size_t rndsiz(void) { return 5 + (random() & 255); }
#endif
#endif

#if 0
static void s_ms_s(char * buf, time_t s, long ns)
{
    buf[2] = buf[5] = buf[12] = ':'; buf[8] = ',';
    buf[7] = '0' + s % 10; s /= 10;
    buf[6] = '0' + s % 6; s /= 6;
    buf[4] = '0' + s % 10; s /= 10;
    buf[3] = '0' + s % 6; s /= 6;
    buf[1] = '0' + s % 10; s /= 10;
    buf[0] = '0' + s % 10;

    ns = ns / 1e6; buf[9] = '0' + ns % 10;
    ns = ns / 10; buf[10] = '0' + ns % 10;
    ns = ns / 10; buf[11] = '0' + ns;
}
#endif

static void s_ms_s(char * buf, time_t s, long ns)
{
#if TEST & 2
    s = 0; ns = 0;
#endif
    buf[2] = buf[9] = ':'; buf[5] = ','; buf[10] = ' ';
    buf[4] = '0' + s % 10; s /= 10;
    buf[3] = '0' + s % 6; s /= 6;
    buf[1] = '0' + s % 10; s /= 10;
    buf[0] = '0' + s % 10;

    ns = ns / 1e6; buf[8] = '0' + ns % 10;
    ns = ns / 10;  buf[7] = '0' + ns % 10;
    ns = ns / 10;  buf[6] = '0' + ns;
}

static void sigact(int sig, void (*handler)(int))
{
    struct sigaction action;

    memset(&action, 0, sizeof action);
    action.sa_handler = handler;
    action.sa_flags = SA_RESTART|SA_NOCLDSTOP; /* NOCLDSTOP needed if ptraced */
    sigemptyset(&action.sa_mask);
    sigaction(sig, &action, NULL);
}

static void signaled(int sig)
{
    fprintf(stderr, "Got signal %d. Sending to %d...\n", sig, cpid);
    kill(cpid, sig);
}

#define BUFSIZE 16384

static char ** split_argv(int argc, char * argv[], char buf[static BUFSIZE])
{
    char *argv1 = argv[1];
    int ac = 0;
    char *p = argv1;
    /* count args */
    while (1) {
        while (*p == ' ') p++;
        if (*p++ == '\0') break;
        ac++;
        while (*p != ' ') {
            if (*p == '\0') goto _break2;
            p++;
        }
    }
_break2:
    if (ac < 3) {
        fprintf(stderr, "((ofile,) '.' and) command [initial-args] missing\n");
        return NULL;
    }
    ac += argc;
    if ((ulong)ac > (BUFSIZE - 32) / sizeof(char**) ) abort(); // unlikely
    char ** av = (char **)buf; // we trust buf aligned...
    av[0] = argv[0];
    int c = 1;
    p = argv1;
    /* fill args */
    while (1) {
        while (*p == ' ') p++;
        if (*p == '\0') break;
        av[c++] = p++;
        while (*p != ' ') {
            if (*p == '\0') goto _break4;
            p++;
        }
        *p++ = '\0';
    }
_break4:
    if (av[2][0] != '.' || (av[2][1] != '\0' &&
                            (av[2][1] != '.' || av[2][2] != '\0'))) {
        fprintf(stderr, "2nd arg '%s' not '.|..'\n", av[2]);
        return NULL;
    }
    for (int i = 2; i < argc; i++) {
        av[c++] = argv[i];
    }
    av[c++] = NULL;
#if 0
    printf("%d %d %d\n", argc, ac, c);
    for (int i = 0; i < ac; i++) printf("%d: %s\n", i, av[i]);
    exit(0);
#endif
    return av;
}

int main(int argc, char * argv[])
{
    if (argc < 3) {
        fprintf(stderr, "\nUsage: %s ofile (.|..) command [args]\n"
                "or\n" "    #! %s ofile (.|..) command [initial args]\n\n"
                "(latter in \"hashbang\" line)\n", argv[0], argv[0]);
        return 1;
    }
    char buf[BUFSIZE + 12];
    if (argv[2][0] == '.' && (argv[2][1] == '\0' ||
                              (argv[2][1] == '.' && argv[2][2] == '\0'))) {
        if (argc == 3) {
            fprintf(stderr, "command [args] missing\n");
            return 1;
        }
    } else {
        argv = split_argv(argc, argv, buf);
        if (argv == NULL) return 1;
    }
    int fd = open(argv[1], O_WRONLY|O_CREAT|O_TRUNC, 0644);
    if (fd < 0) err(1, "cannot open file %s", argv[1]);
    ffd = fd;
    char dots[] = ".................................."
        "..................................";
    /* note: no SIGCHLD handling, expects final EOF from child fd */
    sigact(SIGINT, signaled);
    sigact(SIGTERM, signaled);
    if (argv[2][1] == '.')
    {   // wait until (near) next sec
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec = 0;
        ts.tv_nsec = 1000000000 - ts.tv_nsec;
        nanosleep(&ts, NULL);
    }
    tsmsgf("%s ...\n", argv[3]);
    run_command(argv + 3);
    const char * logfile = argv[1];
#define argv argv_do_not_use_anymore
    // split_argv() -returned argv is clobbered after next line //
    memcpy(buf + 11, "start\n", 6);
    struct timespec start_tv, tv;
    clock_gettime(CLOCK_REALTIME, &start_tv);
    s_ms_s(buf, 0, start_tv.tv_nsec);
    write(fd, buf, 17);
    int l = snprintf(buf + 16, sizeof buf - 20,
                     " (dot (.) per line, full log in '%s')", logfile);
    write(1, buf, 16 + l);
    int ts = 1;
    int dc = 0;
    while (1) {
#if !TEST
        l = read(0, buf + 11, BUFSIZE);
#else
        l = read(0, buf + 11, rndsiz());
#endif
        clock_gettime(CLOCK_REALTIME, &tv);
        if (l <= 0) break;
        char *pp = buf, *p = buf + 11;
        int i = 0;
        while (i++ < l) {
            if (*p++ == '\n') {
                int cdc = dc++ & 63;
                if (ts || cdc == 0) {
                    s_ms_s(pp, tv.tv_sec - start_tv.tv_sec, tv.tv_nsec);
                }
                if (cdc == 0) {
                    int dl = snprintf(dots, 24, "%d", dc); dots[dl] = '.';
                    struct iovec iov[3] = {
                        { .iov_base = (char*)(intptr_t)"\n", .iov_len = 1 },
                        { .iov_base = pp, .iov_len = 11 },
                        { .iov_base = dots, .iov_len = 1 }
                    };
                    (void)!writev(1, iov, 3);
                } else {
                    write(1, dots + cdc, 1);
                }
                if (ts == 0) {
                    pp += 11;
                    ts = 1;
                }
                write(fd, pp, p - pp);
                pp = p - 11;
            }
        }
        if (pp < p - 11) {
            if (ts) {
                s_ms_s(pp, tv.tv_sec - start_tv.tv_sec, tv.tv_nsec);
            }
            else {
                pp += 11;
            }
            write(fd, pp, p - pp);
            ts = 0;
        }
    }
    s_ms_s(buf + 4, tv.tv_sec - start_tv.tv_sec, tv.tv_nsec);
    memcpy(buf + 15, "eof!\n", 5);
    write(fd, buf + 4, 16);
    buf[3] = '\n';
    l = snprintf(buf + 15, 32, "%d eof!\n", dc);
    write(1, buf + 3, 12 + l);
    int wstatus;
    pid_t pid = wait(&wstatus);
    if (pid < 0) edie("wait");
    /*
     * Some checks below are just for "completeness" -- exit anyway...
     */
    int ev = 111;
    if (WIFEXITED(wstatus)) {
        ev = WEXITSTATUS(wstatus);
        tsmsgf("exited, status=%d\n", ev);
    } else if (WIFSIGNALED(wstatus)) {
        ev = WTERMSIG(wstatus);
        tsmsgf("killed by signal %d\n", ev);
    } else if (WIFSTOPPED(wstatus)) {
        ev = WSTOPSIG(wstatus);
        tsmsgf("stopped by signal %d\n", ev);
    } else if (WIFCONTINUED(wstatus)) {
        tsmsgf("continued\n");
    } else {
        tsmsgf("unknown\n");
    }
    return ev;
}
