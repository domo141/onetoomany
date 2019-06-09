#!/usr/bin/env python3
# $ lossybindiff.py $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2019 Tomi Ollila
#	    All rights reserved
#
# Created: Sat 01 Jun 2019 13:19:50 EEST too
# Last modified: Sun 09 Jun 2019 23:36:47 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

from sys import version_info, argv, stdout, stderr
from os import (isatty, dup2, pipe, close, write,
                get_terminal_size, environb, closerange)
from shutil import which
from subprocess import Popen

assert version_info >= (3, 3)

class C:
    red = '\033[38;5;1m'
    res = '\033[m'
    pass


def mko(b):
    bl = [ '%02X' % byte for byte in b ]  # byte.hex() requires python 3.5
    al = [ chr(byte) if byte > 31 and byte < 127 else '.' for byte in b ]
    lb = len(b)
    if lb < 16:
        bl.extend( ( '--' for _ in range(16 - lb)) )
        al.extend( ( ' ' for _ in range(16 - lb)) )
        pass
    bl.insert(8, '')
    al.insert(8, '')
    return ' '.join(bl), ''.join(al)


def mko2(b1, b2):
    bl1 = [ ]; al1 = [ ]
    bl2 = [ ]; al2 = [ ]
    c = 0
    for i1, i2 in zip(b1, b2):
        pre, post = ('', '') if i1 == i2 else (C.red, C.res)
        bl1.append('%s%02X%s' % (pre, i1, post))
        bl2.append('%s%02X%s' % (pre, i2, post))
        al1.append('%s%s%s' % (pre, chr(i1) if i1>31 and i1<127 else '.', post))
        al2.append('%s%s%s' % (pre, chr(i2) if i2>31 and i2<127 else '.', post))
        c += 1
        pass
    for c in range(c, 16):
        if len(b1) > c:
            i = b1[c]
            s = '%s%02X%s' % (C.red, i, C.res)
            a = '%s%s%s' % (C.red, chr(i) if i > 31 and i < 127 else '.', C.res)
        else:
            s = C.red + '--' + C.res if len(b2) > c else '--'
            a = ' '
            pass
        bl1.append(s); al1.append(a)

        if len(b2) > c:
            i = b2[c]
            s = '%s%02X%s' % (C.red, i, C.res)
            a = '%s%s%s' % (C.red, chr(i) if i > 31 and i < 127 else '.', C.res)
        else:
            s = C.red + '--' + C.res if len(b1) > c else '--'
            a = ' '
            pass
        bl2.append(s); al2.append(a)
        pass
    bl1.insert(8, '')
    bl2.insert(8, '')
    al1.insert(8, '')
    al2.insert(8, '')
    return ' '.join(bl1), ''.join(al1), ' '.join(bl2), ''.join(al2)


def outputdiff(pos, dropped, lead1, lead2, diffr4, diffrr):
    if not outputdiff.called: print('-' * 145); outputdiff.called = True
    if lead1 is not None:
        bl, al = mko(lead1)
        print('%08x  %s  %s | %s  %s' % (pos - 32, bl, al, bl, al))
        pass
    if lead2 is not None:
        bl, al = mko(lead2)
        print('%08x  %s  %s | %s  %s' % (pos - 16, bl, al, bl, al))
        pass
    for l, r in diffr4:
        bl, al, br, ar = mko2(l, r)
        print('%08x  %s  %s | %s  %s' % (pos, bl, al, br, ar))
        pos += 16
        pass
    if dropped:
        print(' - ' * 4,
              '%d bytes of potential differences not shown' % dropped,
              ' - ' * 27)
        pos += dropped
        pass
    for l, r in diffrr:
        bl, al, br, ar = mko2(l, r)
        print('%08x  %s  %s | %s  %s' % (pos, bl, al, br, ar))
        pos += 16
        pass
    print('-' * 145)
    pass
outputdiff.called = False


def main():
    if (len(argv) > 1 and argv[1] in ('.', '..', '/', '//')):
        mode = argv[1]
        argv.pop(1)
    else:
        mode = ''
        pass

    if len(argv) != 3:
        print('\nUsage: %s [mode] file1 file2' % argv[0], file=stderr)
        raise SystemExit("\nmode options:"
                         "\n  '.' -- make terminal 145 colums wide temporarily"
                         "\n '..' -- show differences in urxvt or xterm"
                         "\n  '/' -- do not run through less, show colors"
                         "\n '//' -- do not run through pager, no colors\n")
    closerange(3, 9);
    fn1 = argv[1]; fp1 = open(fn1, 'rb')
    fn2 = argv[2]; fp2 = open(fn2, 'rb')

    ts = None
    if mode in ('/', '//'):
        popenargs = None
        if mode == '//':
            C.red, C.res = '', ''
            pass
        pass
    elif mode == '..':
        cmd = which('urxvt')
        if cmd is None:
            cmd = which('xterm')
            if cmd is None:
                raise SystemExit("No urxvt(1) nor xterm(1) found in PATH")
            pass
        title = '%s  !  %s' % ( fn1.split('/')[-1], fn2.split('/')[-1] )
        popenargs = (cmd, '-g', '145x24', '-fg', '#bbbbbb', '-bg', 'black',
                     '-title', title, '-e',  '/bin/sh', '-c', 'exec less <&8')
        infd = 8;
        pass
    else:
        if not isatty(1):
            popenargs = None
            C.red, C.res = '', ''
        else:
            popenargs = ('less',)
            infd = 0;
            ts = get_terminal_size(1)
            if ts.columns >= 145:
                ts = None
            else:
                if mode == '':
                    raise SystemExit('145+ column terminal required --' +
                                     ' current columns: %d' % ts.columns)
                else:
                    dup2(1, 7)
                    write(7, b'\033[8;%d;%dt' % (ts.lines, 145))
                    pass
                pass
            pass
        pass

    eof = False
    lead1 = None
    lead2 = None
    pos = -16
    diffr4 = None
    diffrr = [ ]
    dropped = 0
    same = 0

    if popenargs is not None:
        environb[b'LESS'] = b'mdeQMiR'
        # luo pipe subprocessille, duppaa 1:seen
        def pxfn():
            dup2(pxfn.rfd, infd)
            closerange(3, 8)
            pass
        pxfn.rfd, pxfn.wfd = pipe()

        popen = Popen(popenargs, preexec_fn = pxfn)

        dup2(pxfn.wfd, 1)
        close(pxfn.rfd)
        close(pxfn.wfd)
        pass

    while not eof:
        pos += 16
        blk1 = fp1.read(16)
        blk2 = fp2.read(16)
        if blk1 == b'' or blk2 == b'': eof = True
        if blk1 == b'' and blk2 == b'': break

        if blk1 == blk2:
            lead1 = lead2
            lead2 = blk1
            continue

        dpos = pos
        diffr4 = [ ( blk1, blk2 ) ]

        while not eof:
            pos += 16
            blk1 = fp1.read(16)
            blk2 = fp2.read(16)
            if blk1 == b'' or blk2 == b'': eof = True
            if blk1 == b'' and blk2 == b'': break

            if blk1 == blk2:
                same += 1
                if same == 4:
                    l1, l2 = diffr4.pop()[0], blk1
                    outputdiff(dpos, 0, lead1, lead2, diffr4, [ ])
                    diffr4 = None
                    same = 0
                    lead1, lead2 = l1, l2
                    break
                pass
            else:
                same = 0
                pass

            if len(diffr4) < 4:
                diffr4.append( (blk1, blk2) )
                continue

            diffrr = [ ( blk1, blk2 ) ]
            dropped = 0
            while not eof:
                pos += 16
                blk1 = fp1.read(16)
                blk2 = fp2.read(16)
                if blk1 == b'' or blk2 == b'': eof = True
                if blk1 == b'' and blk2 == b'': break

                if blk1 == blk2:
                    same += 1
                    if same == 4:
                        l1, l2 = diffrr.pop()[0], blk1
                        outputdiff(dpos, dropped, lead1, lead2, diffr4, diffrr)
                        diffr4 = None
                        diffrr = [ ]
                        dropped = 0
                        same = 0
                        lead1, lead2 = l1, l2
                        break
                else:
                    same = 0
                    pass

                diffrr.append( (blk1, blk2) )
                if len(diffrr) > 7:
                    diffrr.pop(0)
                    dropped += 16
                    pass
                pass
            break
        pass

    if diffr4 is not None:
        dl = len(diffrr)
        if same == 3:
            if dl > 0: diffrr.pop(); dl -= 1
            else: diffr4.pop()
            same = 2
            pass
        dl = dl - same
        if dl > 4:
            diffrr.pop(0); dropped += 16
            if dl > 5: diffrr.pop(0); dropped += 16
            if dl > 6: diffrr.pop(0); dropped += 16
            pass
        outputdiff(dpos, dropped, lead1, lead2, diffr4, diffrr)
        pass

    stdout.flush()
    #stdout.close()
    close(1)

    if popenargs is not None:
        popen.wait()
        pass
    if ts is not None:
        write(7, b'\033[8;%d;%dt' % (ts.lines, ts.columns))
        pass
    pass


if __name__ == '__main__':
    main()
    pass  # pylint: disable=W0107
