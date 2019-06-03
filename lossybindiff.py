#!/usr/bin/env python3
# $ lossybindiff.py $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2019 Tomi Ollila
#	    All rights reserved
#
# Created: Sat 01 Jun 2019 13:19:50 EEST too
# Last modified: Mon 03 Jun 2019 22:00:00 +0300 too

# SPDX-License-Identifier: BSD 2-Clause "Simplified" License

# wip code, going to field-tests... that said, pretty good already!
# wat is missing, is separate terminal and temporary terminal resize
# options, some usage info and so on...

import sys

c_red = '\033[38;5;1m'
c_res = '\033[m'

def mko(b):
    bl = [ '%02X' % byte for byte in b ]  # byte.hex() requires python 3.5
    al = [ chr(byte) if byte > 31 and byte < 127 else '.' for byte in b ]
    lb = len(b)
    if lb < 16:
        bl.extend( ( '  ' for _ in range(16 - lb)) )
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
        pre, post = ('', '') if i1 == i2 else (c_red, c_res)
        bl1.append('%s%02X%s' % (pre, i1, post))
        bl2.append('%s%02X%s' % (pre, i2, post))
        al1.append('%s%s%s' % (pre, chr(i1) if i1>31 and i1<127 else '.', post))
        al2.append('%s%s%s' % (pre, chr(i2) if i2>31 and i2<127 else '.', post))
        c += 1
        pass
    if c < 16:
        bl1.extend( ( '  ' for _ in range(16 - c)) )
        bl2.extend( ( '  ' for _ in range(16 - c)) )
        al1.extend( ( ' ' for _ in range(16 - c)) )
        al2.extend( ( ' ' for _ in range(16 - c)) )
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
    if len(sys.argv) != 3:
        print('\nUsage: %s file1 file2' % sys.argv[0], file=sys.stderr)
        raise SystemExit("Note: requires 145-character wide terminal\n")
    fn1 = sys.argv[1]; fp1 = open(fn1, 'rb')
    fn2 = sys.argv[2]; fp2 = open(fn2, 'rb')

    eof = False
    lead1 = None
    lead2 = None
    pos = -16
    diffr4 = None
    diffrr = [ ]
    dropped = 0
    same = 0

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


if __name__ == '__main__':
    main()
    pass  # pylint: disable=W0107
