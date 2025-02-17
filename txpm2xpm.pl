#!/usr/bin/perl
# -*- mode: cperl; cperl-indent-level: 4 -*-
# $ txpm2xpm.pl $
#
# Author: Tomi Ollila -- too ät iki piste fi
#
#	Copyright (c) 2021 Tomi Ollila
#	    All rights reserved
#
# Created: Fri 07 May 2021 21:21:03 EEST too
# Last modified: Mon 17 Feb 2025 17:52:20 +0200 too

# Help at the end of this file.

# SPDX-License-Identifier: MIT
# The 16-pixel image sample is originally found in X11
# (cannot find it anymore, may be embedded somewhere)...
# Found same construct in one bathroom so maybe it is
# safe against any potential litigation...

use 5.8.1;
use strict;
use warnings;

die "Usage: $0 (-h | input-files | input-file '-')\n" unless @ARGV;

if ($ARGV[0] eq '-h') {
    open I, '<', $0 or die "Opening '$0': $!\n";
    while (<I>) { last if /^__END__/ }
    print $_ while (<I>);
    print "\n";
    exit
}

my $fname;
sub fldie(@) { die "$fname:$.: ", @_, "\n" }

my (%colors, $colors, $colchk);
my (@pix, $pxw, @ppix);

my $verbose = 1;

my $oname = do {
    if (@ARGV == 2 and $ARGV[1] eq '-') { pop @ARGV; '.' }
    else { '' }
};

sub pixwrk();

foreach (@ARGV) {
    warn("Cannot open $_: $!. skipping\n"), next unless open I, '<', $_;
    eval "\$colchk = sub { \$_ }";
    %colors = ();
    $colors = chr(0);
    @pix = ();
    $fname = $_;
    if ($oname eq '') {
	# basename & suffix after last . (or e.g. '.foo' if .../.foo)
	s|^(?:.*/)? (.+?) (?:[.][^.]*)? $ |$1|x;
	$oname = $_ . '.xpm'
    }

    while (<I>) {
	last if /^\s*::\s+txpm\s+::\s/;
	next if /^\s*$/;
	chomp;
	fldie "'$_': unknown line (missing :: txpm :: line)"
    }
    while (<I>) {
	s/(?:^|\s+);;\s.*//; # drop comments -- content starting with '[^ ];; '
	pixwrk, next if /^\s*::\s+txpm\s+::\s/;
	next if /^\s*$/; # empty line
	if (/^\s*(\S\S+):\s+(.*?)\s*$/) {
	    $oname = $2, next if $1 eq '>>>';
	    @pix = @ppix, next if $1 eq '<<<';
	    fldie "'$1': Unknown input\n"
	}
	my $c = 0;
	while( /(?:^|\s)(\S)\s+(\S+)/g ) {
	    $c = 1;
	    #print "$1 -- $2\n";
	    $colors{$1} = $2
	}
	if ($c) {
	    $colors = join('', sort keys %colors);
	    #arn "\$colchk = sub { tr/$colors//d }";
	    eval "\$colchk = sub { tr/$colors//d }";
	    #print $colors, "\n";
	    next
	}
	if (/^\s*(\S\S\S+)\s*$/) {
	    my $pw = length $1;
	    if (@pix) {
		fldie "'$1': width change ($pw != $pxw)" unless $pw == $pxw
	    } else {
		fldie "'>>>:' not given before pixel lines" unless $oname;
		$pxw = $pw
	    }
	    push @pix, $1;
	    $_ = $1; &$colchk;
	    fldie "'$_': unknown color chars in '$pix[$#pix]'\n" if $_;
	    next
	}
	fldie "unknown line: $_"
    }
    pixwrk if @pix >= 2
}

sub pixwrk()
{
    fldie "At least 2 \"rows\" of pixels required\n" unless @pix >= 2;
    @ppix = @pix;
    my $apix = join('', @pix);
    my @aclrs;
    foreach (split '', $colors) {
	push @aclrs, $_ if index($apix, $_) >= 0
    }
    my @ofile;
    #open O, '>', $oname or die $!;
    #select O;
    push @ofile, "/* XPM */\n", "static char *pix[] = {\n",
      "/* columns rows colors chars-per-pixel */\n",
      '"', $pxw, ' ', scalar @pix, ' ', scalar @aclrs, " 1\",\n";
    foreach (@aclrs) {
	push @ofile, "\"$_ c ", $colors{$_}, "\",\n"
    }
    push @ofile, "/* pixels */\n";
    my $l = pop @pix;
    push @ofile, '"', $_, '",', "\n" foreach (@pix);
    push @ofile, '"', $l, '"', "\n};\n";
    @pix = ();
    my $ofile = join '', @ofile;
    @ofile = ();
    if ($oname eq '.') {
	syswrite STDOUT, $ofile;
	$oname = '';
	return
    }
    if (-e $oname) {
	open J, '<', $oname or die "Cannot read '$oname': $!\n";
	sysread J, my $ifile, 2e6;
	close J;
	my $isize = length $ifile;
	my @st = stat $oname;
	die "Size mismatch ($isize != $st[7]) in '$oname'\n"
	  unless $isize == $st[7];
	if ($ifile eq $ofile) {
	    print "$fname:$.: '$oname' exists and is same as in '$fname'.\n"
	      if $verbose;
	    $oname = '';
	    return
	}
	my $arname = $oname . '.ar';
	print "$fname:$.: '$oname' exists. Archiving it to '$arname'.\n"
	  if $verbose;
	my $arsize = -s $arname;
	open O, '>>', $arname or fldie "Cannot write to '$arname': $!\n";
	print O "!<arch>\n" unless $arsize;
	my @tm = gmtime $st[9];
	my $ts = sprintf "%d%02d%02d-%02d%02d%02d",
	  $tm[5] + 1900, $tm[4] + 1, $tm[3], $tm[2], $tm[1], $tm[0];
	#hdr fmt: fname mod   uid   gid   mode    size magic
	printf O "%-16s%-10d  0     0     100644  %-10d\140\012",
	  $ts, $st[9], $isize;
	print O $ifile;
	print O "\000" if $isize & 1;
	close O
    }
    print "$fname:$.: Writing to '$oname'.\n" if $verbose;
    open O, '>', $oname or die "Cannot write to '$oname': $!\n";
    syswrite O, $ofile;
    close O;
    $oname = ''
}
__END__

txpm2xpm - convert 'text pixmap' files to xpm files

The 2 argument format  txpm2xpm.pl input-file -  converts input-file
to xpm format and writes it to stdout. The data can, for example, be
piped to  | feh --bg-tile --no-fehbg -

Otherwise input-files are converted to xpm and written to files. By
default (first) output is written to filename based on current input
file name, last .* part removed and replaced with .xpm...

Sample .txpm file content between ---8<--- blocks:
---8<-----8<-----8<-----8<-----8<-----8<-----8<---
:: txpm :: -- first non-empty line has to start with :: txpm ::

;; two ;;'s (and one space) start comments in line. after
;; comment removal if line is empty it is ignored. In all
;; cases leading and trailing whitespace is ignored.

x #555 . black ;; one char followed by space and then
               ;; text content will set colors

.x..  ;; the pixels of a picture, colors have to be defined
x...  ;; in file before use (validation). all pixel lines
..x.  ;; have to have same amount of "columns".
...x  ;; this pix is traditional X11 background image.

;; if file ended here, the conversion to xpm would happen
;; and program ended successfully.

:: txpm :: -- line starting like this allows more images
           ;; to be defined in one file

>>>: x11-red ;; with >>>: prefix a name to next image in file
             ;; can be given (must be for other than 1st image)

x #f00 ;; change color 'x' in pixel array from #555 to red

<<<: . ;; re-use the X11 background image (note '.' there)

---8<-----8<-----8<-----8<-----8<-----8<-----8<--

If output file exist and has same content as the one to be
written, file write is skipped. If content differs, then
old content are written to an ar(5) archive; to the file
named with suffix '.ar'.

Pixel characters (one chr per pixel) and color values are
converted "verbatim" to xpm format.
