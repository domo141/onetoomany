#if 0 /* -*- mode: c; c-file-style: "stroustrup"; tab-width: 8; -*-
 set -euf; trg=${0##*''/}; trg=${trg%.c}; test ! -e "$trg" || rm "$trg"
 case ${1-} in '') set x -O2; shift; esac
 #case ${1-} in '') set x -ggdb; shift; esac
 set -x; exec ${CC:-gcc} -std=c99 "$@" -o "$trg" "$0"
 exit $?
 */
#endif
/*
 * $ simplecom.c $
 *
 *	Copyright (c) 2011 Tomi Ollila
 *	    All rights reserved
 *
 * Created: Fri 14 Oct 2011 19:16:05 EEST too
 * Last modified: Sat 24 Oct 2020 17:00:17 +0300 too
 */

/* SPDX-License-Identifier: BSD-2-Clause */

/* /sys/bus/usb-serial/devices/ttyUSB0/power/control */

/* -- embedded more-warnings.h -- */

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

#if __GNUC__ >= 7
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

// -Wformat=2 ¡currently! (2020-10-10) equivalent of the following 4
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

/* name and interface from talloc.c */
#ifndef discard_const_p // probably never defined, but...
//#include <stdint.h>
#if defined (__INTPTR_TYPE__) /* e.g. gcc 4.8.5 - */
#define discard_const_p(type, ptr) ((type *)((__INTPTR_TYPE__)(ptr)))
#elif defined (__PTRDIFF_TYPE__) /* e.g. gcc 4.4.6 */
#define discard_const_p(type, ptr) ((type *)((__PTRDIFF_TYPE__)(ptr)))
#else
#define discard_const_p(type, ptr) ((type *)(ptr))
#endif
#endif

/* -- end of more-warnings.h -- */

#define _DEFAULT_SOURCE // since glibc >= 2.19, overrides the following 2
#define _BSD_SOURCE // for CRTSCTS and cfmakeraw with --std=c99 (linux) //
#define _POSIX_SOURCE

#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <termios.h>
#include <fcntl.h>
#include <sys/poll.h>
#include <errno.h>

// Glibc may make write(2) warn about unused result. the (void) casts in
// writes are used to inform we really don't care if these fails here.
// But that is not enough to silence compiler.
// Unfortunately with this we loose potential future warnings...
#if defined (__GNUC__) && __GNUC__ >= 5
#pragma GCC diagnostic ignored "-Wunused-result"
#endif

struct termios sstio;
static void reset_tty(void)
{
    tcsetattr(0, TCSANOW, &sstio);
    tcsetattr(0, TCSAFLUSH, &sstio);
    (void)write(0, "\n", 1);
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

static void movefd(int o, int n)
{
    if (o == n)
	return;
    dup2(o, n);
    close(o);
}

static void init(const char * port)
{
    int i, cfd;
    struct termios tio;

    for (i = 0; i < 100; i++) {
	cfd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK, 0);
	if (cfd < 0) {
	    if (i == 0) {
		fprintf(stderr, "Cannot open '%s' (\"fix\" /etc/group?): %s.\n",
			port, strerror(errno));
		fprintf(stderr, "Trying to open for 10 seconds, in case the "
			"device is coming up (Ctrl-C to break).\n");
	    }
	    usleep(100000);
	}
	else break;
    }
    if (i >= 100) exit(1);
    movefd(cfd, 3);
    i = fcntl(3, F_GETFL, 0);
    fcntl(3, F_SETFL, i & ~O_NONBLOCK);

    /* serial */
    memset(&tio, 0, sizeof tio);
    // Note: CRTSCTS may cause problems (or maybe I had broken cable...).
    //tio.c_cflag = ( CS8 | CRTSCTS | CLOCAL | CREAD );
    tio.c_cflag = ( CS8 | CLOCAL | CREAD );
    tio.c_iflag = ( IGNPAR );
    cfsetospeed(&tio, B115200);
    cfsetispeed(&tio, B115200);
    /* tio.c_cc[VTIME] = 1; \* one decisecond ... */
    /* tio.c_cc[VMIN] = 80; \* ... test suitable combinations. */
    tcsetattr(3, TCSANOW, &tio);
    tcsetattr(3, TCSAFLUSH, &tio);

    /* tty */
    tcgetattr(0, &sstio);
    atexit(reset_tty);
    sigact(SIGTERM, (void(*)(int))reset_tty);
    memcpy(&tio, &sstio, sizeof tio);
    cfmakeraw(&tio);
    tcsetattr(0, TCSANOW, &tio);
    tcsetattr(0, TCSAFLUSH, &tio);
}

static const char * logfile = NULL;
static int open_logfile(void)
{
    int logfd = open(logfile, O_WRONLY|O_CREAT|O_APPEND, 0644);
    if (logfd < 0) return logfd;
    movefd(logfd, 4);
    return 4; /* main() cares, signal does not */
}

int main(int argc, char * argv[])
{
    if (argc != 2 && argc != 3) {
	printf("Usage: %s port [logfile]\n", argv[0]);
	exit(1);
    }

    for (int i = 3; i < 9; i++)
	close(i);

    if (argc == 3) {
	logfile = argv[2];
	int logfd = open_logfile();
	if (logfd < 0) {
	    fprintf(stderr, "Cannot open log file %s: %s\n",
		    argv[2], strerror(errno));
	}
	/* reopen on arrival of sigusr1 -- see -Wcast-function-type in
	   gcc manual page for reason for (void(*)(void) */
	sigact(SIGUSR1, (void(*)(int))(void(*)(void))open_logfile);
    }
    const char * port = argv[1];
    init(port);

    struct pollfd pfd[2];
    pfd[0].fd = 0;
    pfd[1].fd = 3;
    pfd[0].events = pfd[1].events = POLLIN;

    printf("Simplecom started: pid %d (Send SIGTERM to exit "
	   "-- e.g. pkill simplecom).\r\n",
	   getpid());

    while (poll(pfd, 2, -1) > 0) {
	char buf[1024];
	if (pfd[0].revents & POLLIN) {
	    int len = read(0, buf, sizeof buf);
	    if (len <= 0)
		exit(-len);
	    (void)write(3, buf, len);
	}
	if (pfd[1].revents & POLLIN) {
	    int len = read(3, buf, sizeof buf);
	    if (len <= 0)
		exit(-len);
	    if (logfile != NULL)
		(void)write(4, buf, len);
	    (void)write(0, buf, len);
	}
    }
    return 0;
}
