#if 0 /* -*- mode: c; c-file-style: "stroustrup"; tab-width: 8; -*-
 set -euf
 if test $# -ge 2 && test "$1" = -o
 then trg=$2; shift 2
 else trg=${0##*''/}; trg=${trg%.c}
 fi
 test ! -e "$trg" || rm "$trg"
 test $# = 0 && set -- -O2
 #test $# = 0 && set -- -ggdb
 set -x; exec ${CC:-gcc} -std=c99 "$@" -o "$trg" "$0"
 exit $?
 */
#endif
/*
 * $ connect-forward.c $
 *
 * Author: Tomi Ollila -- too ät iki piste fi
 *
 *      Copyright (c) 2022 Tomi Ollila
 *          All rights reserved
 *
 * Created: Tue 19 Apr 2022 19:21:26 EEST too
 * Last modified: Tue 19 Apr 2022 22:51:49 +0300 too
 */

// usage for compilation: sh connect-forward.c [-o outfile] [compiler options]

// SPDX-License-Identifier: BSD-2-Clause

// this program listens 127.0.0.1:8080 for CONNECT host:port HTTP/1.1
// requests, connects to host:port and forwards traffic between local
// connection and the remore host:port

// my use case for this is to run this in a host that only allows
// process named 'curl' to access network. so i compile this as
// $ sh connect-forward.c -o curl  and then (after running ./curl &) e.g.
// $ all_proxy=127.0.0.1:8080 git pull
// (naming `git` as `curl` does not help, as it exec's
//  other program to communicate with https server)

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
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/poll.h>
#include <netinet/in.h>
#include <netdb.h>
#include <errno.h>

#define null NULL

static void vwarn(const char * format, va_list ap)
{
    int error = errno;

    //fputs(timestr(), stderr);
    vfprintf(stderr, format, ap);
    if (format[strlen(format) - 1] == ':')
        fprintf(stderr, " %s\n", strerror(error));
    else
        fputs("\n", stderr);
    fflush(stderr);
}
#if 0
static void warn(const char * format, ...)
{
    va_list ap;

    va_start(ap, format);
    vwarn(format, ap);
    va_end(ap);
}
#endif
static void die(const char * format, ...)
{
    va_list ap;

    va_start(ap, format);
    vwarn(format, ap);
    va_end(ap);
    exit(1);
}

static int xsocket(int domain, int type, int protocol)
{
    int sd = socket(domain, type, protocol);
    if (sd < 0) die("socket:");
    return sd;
}

static int xbind_listen_tcp4_socket(/*const char * addr, int port*/void)
{
    int sd = xsocket(AF_INET, SOCK_STREAM, 0);
    int one = 1;

    setsockopt(sd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    struct sockaddr_in iaddr = {
        .sin_family = AF_INET,
        .sin_port = htons(8080)
    };
    // set bind address as 127.0.0.1 for now... //
    ((char *)&iaddr.sin_addr)[0] = 127; ((char *)&iaddr.sin_addr)[3] = 1;

    if (bind(sd, (struct sockaddr *)&iaddr, sizeof iaddr) < 0)
        die("bind:");

    if (listen(sd, 5) < 0)
        die("listen:");

    return sd;
}

static int do_connect(char * remote)
{
    char * p = strchr(remote, ':');
    if (p == null)
        die("Remote in CONNECT message lacks ':'");
    *p++ = '\0';

    struct addrinfo * ai;
    // hint, if ever add bind address use getaddrinfo... //
    if (getaddrinfo(remote, p, null, &ai) < 0)
        die("getaddrinfo:");

    int sd = xsocket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);

    if (connect(sd, ai->ai_addr, ai->ai_addrlen) < 0)
        die("connect:");

    return sd;
}

#define WriteCS(f, s) write((f), ("" s ""), sizeof (s) - 1)

static void forwarder(int fd)
{
    char buf[65536];
    int len = read(fd, buf, sizeof buf);
    if (len <= 0) {
        if (len == 0)
            die("EOF while reading CONNECT message");
        die("read:");
    }
    /* current version expects whole CONNECT message in one read;
       will happen if sender writes the whole msg in one write(2) */
    if (len < 20)
        die("CONNECT message too short");
    if (memcmp(buf, "CONNECT ", 8) != 0)
        die("CONNECT message does not start with 'CONNECT '");
    buf[len] = '\0';
    char * p = strchr(buf + 8, ' ');
    if (p == null)
        die("CONNECT message lacks ' ' after remote host");
    *p = '\0';
    int rfd = do_connect(buf + 8);
    (void)!WriteCS(fd, "HTTP/1.1 200 OK\r\n\r\n");

    struct pollfd pfd[2];
    pfd[0].fd = fd;
    pfd[1].fd = rfd;
    pfd[0].events = pfd[1].events = POLLIN;

    while (poll(pfd, 2, -1) > 0) {
        if (pfd[0].revents & POLLIN) {
            len = read(fd, buf, sizeof buf);
            if (len <= 0)
                exit(-len);
            (void)!write(rfd, buf, len);
        }
        if (pfd[1].revents & POLLIN) {
            len = read(rfd, buf, sizeof buf);
            if (len <= 0)
                exit(-len);
            (void)!write(fd, buf, len);
        }
    }
}

int main(void)
//int main(int argc, char * argv[])
{
    int ssd = xbind_listen_tcp4_socket();
    while (1) {
        int sd = accept(ssd, null, 0);
        if (sd < 0)
            die("accept:");
        if (fork() != 0) {
            close(sd);
            continue;
        }
        // child //
        close(ssd);
        forwarder(sd);
        close(sd);
        exit(0);
    }
    return 0;
}
