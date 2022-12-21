#if 0 /* -*- mode: c; c-file-style: "stroustrup"; tab-width: 8; -*-
 set -euf; trg=${0##*''/}; trg=${trg%.c}; test ! -e "$trg" || rm "$trg"
 case ${1-} in '') set x -O2; shift; esac
 #case ${1-} in '') set x -ggdb; shift; esac
 set -x; exec ${CC:-gcc} -std=c11 "$@" -o "$trg" "$0"
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
 * Last modified: Wed 21 Dec 2022 22:20:16 +0200 too
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

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
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

int main(int argc, char * argv[])
{
    if (argc < 3) {
        fprintf(stderr, "Usage: %s ofile command [args]\n", argv[0]);
        return 1;
    }
    int fd = open(argv[1], O_WRONLY|O_CREAT|O_TRUNC, 0644);
    if (fd < 0) err(1, "cannot open file %s", argv[1]);
    ffd = fd;
    tsmsgf("%s ...\n", argv[2]);
    run_command(argv + 2);
#define BUFSIZE 16384
    char buf[BUFSIZE + 12];
    memcpy(buf + 11, "start\n", 6);
    struct timespec start_tv, tv;
    clock_gettime(CLOCK_REALTIME, &start_tv);
    s_ms_s(buf, 0, start_tv.tv_nsec);
    write(fd, buf, 17);
    write(1, buf, 16);
    int ts = 1;
    int dc = 0;
    while (1) {
#if !TEST
        int l = read(0, buf + 11, BUFSIZE);
#else
        int l = read(0, buf + 11, rndsiz());
#endif
        if (l <= 0) break;
        if (ts) {
            clock_gettime(CLOCK_REALTIME, &tv);
        }
        char *pp = buf, *p = buf + 11;
        int i = 0;
        while (i++ < l) {
            if (*p++ == '\n') {
                if (ts || dc == 0) {
                    s_ms_s(pp, tv.tv_sec - start_tv.tv_sec, tv.tv_nsec);
                }
                if (dc++ == 0) {
                    struct iovec iov[3] = {
                        { .iov_base = (char*)(intptr_t)"\n", .iov_len = 1 },
                        { .iov_base = pp, .iov_len = 11 },
                        { .iov_base = (char*)(intptr_t)".", .iov_len = 1 }
                    };
                    (void)!writev(1, iov, 3);
                } else {
                    write(1, ".", 1);
                    if (dc > 64) dc = 0;
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
    clock_gettime(CLOCK_REALTIME, &tv);
    s_ms_s(buf, tv.tv_sec - start_tv.tv_sec, tv.tv_nsec);
    memcpy(buf + 11, "eof!\n", 5);
    write(fd, buf, 16);
    write(1, "\n", 1);
    write(1, buf, 16);
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
