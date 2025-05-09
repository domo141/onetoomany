#!/usr/bin/env python
# -*- coding: utf-8 -*-
# $ uni2htmldiff.py $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#       Copyright (c) 2015 Tomi Ollila
#           All rights reserved
#
# Created: Wed 25 Mar 2015 23:15:33 EET too
# Last python2: Mon 27 Apr 2015 20:21:56 +0300 too
# Python3.6+: Thu 17 Apr 2025 13:15:29 +0300 too
# Last modified: Thu 17 Apr 2025 23:34:48 +0300 too

"""Create html page (side-by-side tables) from unified diff input."""

# Todo: Color themes (pre-defined and user-definable (or just let users edit)).

# This software can be accessed or otherwise used by the terms and conditions
# described in PYTHON SOFTWARE FOUNDATION LICENSE VERSION 2. NO WARRANTY!

# ruff: noqa: E701, E702, E741

from difflib import Differ
from getopt import getopt, GetoptError
import sys
import os
import re


def warn(t):
    print(t, file=sys.stderr)
    pass


# global "variables" put in a class; no objects instantiated...
class G:
    version = '1.2'
    verdate = '2025-04-17'
    tabsize = None
    outfile = None
    title = None
    addrem = False
    pass


def yield_lines(files):
    for fn in files:
        #fnr = 0
        if fn == '-':
            fh = sys.stdin
        else:
            fh = open(fn, 'r')
            pass
        for line in fh:
            #fnr = fnr + 1; print(fnr)
            yield line
            pass
        if fn != '-':
            fh.close()
            pass
        yield "#eof"
        pass
    pass


cmap = { '-': 's', '+': 'a', '^': 'c', ' ': None }
bmap = { '-': 't', '+': 'b', ' ': 'p' }


he_re = re.compile(r'(&|>|<|\t)')
#hemap ={ '&': '&amp;', '>': '&gt;', '<': '&lt;', '\t': '·' }
hemap = { '&': '&amp;', '>': '&gt;', '<': '&lt;', '\t': ' ' }
def he(txt):
    return he_re.sub(lambda x: hemap[x.group(0)], txt)


def tdcls(cls, txt):
    return f'<td class="{cls}">{txt}</td>'


def span(cls, txt):
    return '' if txt == '' else f'<span class="{cls}">{txt}</span>'


def onec(clsref, bclsref, txt):
    cls = cmap[clsref]
    bcls = bmap[bclsref]
    txt = txt[2:-1]
    l = []
    def _onec(txt):
        if cls is not None:
            l.append(tdcls(bcls, span(cls, he(txt))))
        else:
            l.append(tdcls(bcls, he(txt)))
            pass
        pass
    while len(txt) > G.linewidth:
        _onec(txt[:G.linewidth])
        txt = txt[G.linewidth:]
        pass
    _onec(txt)
    return l


# regular expression for finding intraline change indices
change_re = re.compile(r'(\++|\-+|\^+)')  # from difflib.py, r added
def mxc(clsref, txt, markers):
    l = []
    bcls = bmap[clsref]

    def _mxc(txt, markers):
        # find intraline changes (store change type and indices in tuples)
        sub_info = []  # from difflib.py, with mods...
        def record_sub_info(match_object, sub_info=sub_info):
            sub_info.append([match_object.group(1)[0], match_object.span()])
            return match_object.group(1)
        change_re.sub(record_sub_info, markers)

        ll = []
        s = 0
        for key,(begin,end) in sub_info:
            if s != begin: ll.append( he(txt[s:begin]) )
            ll.append(span(cmap[key], he(txt[begin:end])))
            s = end
            pass
        e = len(txt)
        if s != e: ll.append(he(txt[s:e]))
        l.append(tdcls(bcls, ''.join(ll)))
        pass

    #print('t:', txt, "\nm:", markers)
    txt, markers = (txt[2:-1], markers[2:-1])

    while len(txt) > G.linewidth:
        _mxc(txt[:G.linewidth], markers[:G.linewidth])
        txt, markers = ( txt[G.linewidth:], markers[G.linewidth:] )
        pass
    _mxc(txt, markers)
    return l


def xcompare(old, new, lines):
    gen = Differ().compare(old, new)
    lines.append(' ')
    lines.append(next(gen))
    try:
        lines.append(next(gen))
        lines.append(next(gen))
        yield lines[1]
    except StopIteration:
        lines.append('X')
        lines.append('X')
        yield lines[1]
        pass
    for line in gen:
        lines.pop(0)
        lines.append(line)
        yield lines[1]
        pass
    while lines[2][0] != 'X':
        lines.pop(0)
        lines.append('X')
        yield lines[1]
        pass
    pass


def print_tr(ln, ltd, rn, rtd):
    print(f'<tr><td class="h">{ln}</td>{ltd}<td class="h">{rn}</td>{rtd}</tr>')
    pass


def drain_wlines(wlines, ln):
    if not wlines: return
    for lines in wlines:
        lnr = ln[0]
        for line in lines:
            print_tr(lnr, line, '', '<td class="n"></td>')
            lnr = '`'
            pass
        ln[0] = ln[0] + 1
        pass
    wlines[:] = []
    pass


def output_same(txtl, ln):
    txt = txtl.pop(0)
    print_tr(ln[0], txt, ln[1], txt)
    for txt in txtl:
        print_tr('`', txt, '`', txt)
        pass
    ln[0] = ln[0] + 1
    ln[1] = ln[1] + 1
    pass


def output_both(txtl, txtr, ln):
    if txtl is not None:
        ln0 = ln[0]
        ln[0] = ln[0] + 1
    else:
        txtl = []
        pass
    ln1 = ln[1]
    ln[1] = ln[1] + 1

    while txtl or txtr:
        if txtl: ltd = txtl.pop(0)
        else: ltd = '<td class="n"></td>'; ln0 = ''
        #ltd =  txtl.pop(0) if txtl else '<td class="n"></td>'
        if txtr: rtd = txtr.pop(0)
        else: rtd = '<td class="n"></td>'; ln1 = ''
        #rtd =  txtr.pop(0) if txtr else '<td class="n"></td>'
        print_tr(ln0, ltd, ln1, rtd)
        ln0 = '`'; ln1 = '`'
        pass
    pass


def dodiff(old, new, ln):
    # check whether last line '-- ' and drop it if so.
    # it is possible very last line of input was '- '
    # but that's just too bad...
    if old and old[-1] == '- \n':
        old.pop()
        pass
    clines = []
    wlines = []
    gen = xcompare(old, new, clines)
    for line in gen:
        #print(line, end='', file=sys.stderr); continue
        lc0 = line[0]
        if lc0 == ' ':
            drain_wlines(wlines, ln)
            output_same(onec(' ', ' ', line), ln)
            continue
        if lc0 == '-':
            lc20 = clines[2][0]
            if lc20 == ' ' or lc20 == '-' or lc20 == 'X':
                wlines.append(onec(lc0, lc0, line))
                continue
            if lc20 == '+':
                if clines[3][0] == '?':
                    wlines.append(onec(' ', '-', line))
                else:
                    wlines.append(onec(lc0, lc0, line))
                continue
            if lc20 == '?':
                drain_wlines(wlines, ln)
                wlines.append(mxc(lc0, line, clines[2]))
                next(gen)
                continue
            raise SystemExit(
                f"Internal Error(1): line '{line}' (next0: {lc20})")
        if lc0 == '+':
            if clines[2][0] == '?':
                output_both(wlines.pop(0), mxc(lc0, line, clines[2]), ln)
                clines[2] = ' ' # to not match next clines[0][0] ever if here
                next(gen)
                continue
            if clines[0][0] == '?':
                output_both(wlines.pop(0), onec(' ', '+', line), ln)
                continue
            output_both(wlines.pop(0) if wlines else None,
                        onec(lc0, lc0, line), ln)
            continue
        raise SystemExit(f"Internal Error(2): line '{line}' (next0 {lc20})")
    drain_wlines(wlines, ln)
    pass


diffline_set = set((' ', '-', '+', '@'))
def print_addrem(gtlt, pm3, cls, name, gen):
    print(f'<p><span class="{cls}"><b><tt>{gtlt} {pm3}'
          ' {he(name)} {pm3}</tt></b></span></p>')
    for line in gen:
        if line[0] not in diffline_set:
            break
        pass
    pass


def print_table(lft, rght):
    print(f'''<table cellspacing="0" cellpadding="0" rules="groups">
<thead><tr><th></th><th>{he(lft)}</th><th></th><th>{he(rght)}</th></tr></thead>
<tbody>''')
    pass


def print_hh(txt):
    print(f'<tr><td colspan="4" class="i">{he(txt)}</td></tr>')
    pass

tab_re = re.compile(r'\t')
def xtab(line):
    sxl = [ 0 ]  # nonlocal not available in python 2 afaik
    def replace_tabs(match_object):
        s = match_object.start() + sxl[0]
        t = (G.tabsize - 1) - s % G.tabsize
        sxl[0] = sxl[0] + t
        return '\t' * (t + 1)  # will be later converted further...
        #return '........'[0:t+1]  # ...(e.g. spaces after diffing)
    return tab_re.sub(replace_tabs, line)
    #return line.expandtabs()


# In diffs, removal of '-- foo/bar' looks like '--- foo/bar'
# and addition of '++ foo/bar' '+++ foo/bar'
# i.e. expect something else to be between diffs...


def diff_loop(gen, ln):
    old = []; new = []
    for line in gen:
        if line[0] == ' ':
            #warn(f"both: {line}")
            line = xtab(line[1:])
            old.append(line)
            new.append(line)
        elif line[0] == '-':
            #warn(f"old: {line}")
            line = xtab(line[1:])
            old.append(line)
        elif line[0] == '+':
            #warn(f"new: {line}")
            line = xtab(line[1:])
            new.append(line)
        elif line[0] == '@':
            #warn(f"next: {line}")
            dodiff(old, new, ln)
            m = diff_re.match(line)  # e.g.  @@ -118,7 +118,7 @@
            if not m:
                warn(f"line '{line}' does not match '@@ +n,n -n,n...'")
                ln = [ -99, -99 ]
            else:
                ln = [ int(m.group(1)), int(m.group(2)) ]
                pass
            print('<tr><td colspan="4" class="h"><hr/></td></tr>')
            print_hh(line.rstrip())
            old = []; new = []
        else:
            #warn(f"end: {line}")
            dodiff(old, new, ln)
            break
        pass
    pass


fn_re = re.compile(r'.*?\s([^\t\n]+)')
diff_re = re.compile(r'@@\s+-(\d+),\d+\s+[+](\d+),\d')  # note: w/o ^ (re.match)
def uni2htmldiff(files):
    gen = yield_lines(files)
    for left in gen:
        if left.startswith("--- "):
            #warn(left)
            #left = left.split(' ')[1].split('\t')[0].rstrip()
            left = fn_re.match(left).group(1)  # this allows fn trailing spaces
            right = next(gen)
            if not right.startswith("+++ "):
                warn(f"line '{right}' does not start with '+++ '")
                continue
            #warn(right)
            right = fn_re.match(right).group(1)
            rns = next(gen)
            if not rns.startswith("@@ "):
                warn(f"line '{rns}' does not start with '@@ '")
                continue
            #warn(rns)
            m = diff_re.match(rns)  # e.g.  @@ -118,7 +118,7 @@
            if not m:
                warn(f"line '{rns}' does not match '@@ +n,n -n,n...'")
                continue
            ln = [ int(m.group(1)), int(m.group(2)) ]
            if G.addrem:
                if ln[0] == 0:
                    print_addrem('>', '+++', 'b', right, gen)
                    continue
                elif ln[1] == 0:
                    print_addrem('<', '---', 't', left, gen)
                    continue
                pass
            print_table(left, right)
            print_hh(rns)
            diff_loop(gen, ln)
            print('</tbody>\n</table>')
            pass
        pass
    pass


def check_files(files):
    _set = set()
    for fn in files:
        if fn in _set:
            raise SystemExit(f"File '{fn}' seen already")
        _set.add(fn)
        if fn != '-' and not os.path.isfile(fn):
            raise SystemExit(f"'{fn}': no such file")
        pass
    pass


def output_htmlhead():
    print(f'''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<title>{he(G.title)}</title>
<style>
table {{ font-family: Courier;  font-size: 9pt;  line-height: 1.0;
        border: inset 3px;  color: #000000;
        margin-top: 1em;  margin-bottom: 1em;
}}
hr {{ display: block;
     margin-top: 2px;  margin-bottom: 0px;
     margin-left: 0px;  margin-right: 0px;
     border-style: solid black;  border-width: 1px;
}}
p {{ margin: 3px; }}
th {{ background-color: #bbbbbb;  padding-top: 1px;  padding-bottom: 2px; }}
td {{ padding: 0px 1px; white-space: pre; }}
.h {{ background-color: #cccccc;  text-align: right; }}
.i {{ background-color: #cccccc;  text-align: center; padding-bottom: 2px; }}
.p {{ background-color: #ffffff; }}
.n {{ background-color: #eeeeee; }}
.a {{ background-color: #aaffaa; }}
.b {{ background-color: #e8ffe8; }}
.c {{ background-color: #ffff77; }}
.s {{ background-color: #ffaaaa; }}
.t {{ background-color: #ffe8e8; }}
</style>
</head>
<body>''')
    pass


def usage():
    import textwrap
    sys.stdout = sys.stderr
    print(textwrap.fill(f'Usage: {sys.argv[0]}'
                        '[-o_file] [-t_title] [-x_tabsize] [-B] '
                        'linewidth (diff-file|-)...',
                        75, subsequent_indent=' ' * 10,
                        break_on_hyphens=False).replace('_', ' '))

    print("""Options:
    -o file      output file (default: standard output)
    -t title     title of html document (default: 'd i f f')
    -x tabsize   size of tab in characters (default: 8)

    -B  suppress diff when full file is added or removed

    linewidth  characters per line before wrapping
    diff-file  input file(s) (when file is '-', read standard input)
""")
    print(sys.argv[0], G.version, '', G.verdate)
    raise SystemExit(1)


def getnumber(s):
    try:
        return int(s)
    except ValueError:
        raise SystemExit(f"'{s}': not a number")
    pass


def setgopt(name, value, opt):
    if getattr(G, name, None) is not None:
        raise SystemExit(f"'{opt}' may be specified only once")
    setattr(G, name, value)
    pass


if __name__ == '__main__':
    try:
        # (old) code from 2015 - but works - should be in fn() but so not #
        opts, args = getopt(sys.argv[1:], "f:t:o:T:x:Bh")
    except GetoptError as e:
        raise SystemExit(f'{e}')
    for o, a in opts:
        if o == '-o':
            setgopt('outfile', a, o)
        elif o == '-t':
            setgopt('title', a, o)
        elif o == '-x':
            setgopt('tabsize', a, o)
        elif o == '-B':
            G.addrem = True
        elif o == '-h':
            args = []
        else:
            raise SystemExit(f"internal error: '{o}': option not handled")
        pass

    if len(args) < 2:
        usage()
        pass

    G.linewidth = getnumber(args.pop(0))
    if G.linewidth < 10 or G.linewidth > 9999:
        raise SystemExit(f"'{G.linewidth}': value not between 10 and 9999")

    if G.outfile is None:
        G.outfile = '(stdout)'
        pass
    else:
        sys.stdout = open(G.outfile, "w")
        pass
    if G.title is None: G.title = 'd i f f'

    if G.tabsize is None:
        G.tabsize = 8
    else:
        G.tabsize = getnumber(G.tabsize)
        if G.tabsize < 1 or G.tabsize >= G.linewidth:
            raise SystemExit(
                f"'{G.tabsize}': value not between 1 and {G.linewidth - 1}")
        pass

    check_files(args)
    output_htmlhead()
    uni2htmldiff(args)
    print('<span style="border-top: 1px solid black">',
          '<a href="uni2htmldiff.py">uni2htmldiff.py</a>',
          '</span>', '</body>', '</html>', sep='\n')
    pass  # pylint: disable=W0107
#eof
