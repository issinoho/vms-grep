#!/usr/bin/env python3
"""Generate VMS probe programs for the autoconf checks in a configure script.

Extracts the function, header, declaration, type and member checks that an
autoconf-generated configure script performs, and writes one small C program
per check plus a manifest.  tools/vms_cfgprobe.com compiles (and for function
checks, links) each program on VMS; tools/cfgprobe_site.py turns the results
into a config.site that the host-side configure run consumes.

Usage: cfgprobe_gen.py <configure> <outdir>
"""
import os
import re
import sys

# Autoconf's $ac_includes_default, minus headers it guards with HAVE_ macros
# that VMS has anyway.
INCLUDES_DEFAULT = """\
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <stdint.h>
#include <strings.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
"""


def shell_dq_args(text, pos, count):
    """Parse up to COUNT double-quoted shell words starting at POS.

    Returns the list of unescaped strings, or None if a word is not a plain
    double-quoted string (e.g. an unquoted $variable).
    """
    args = []
    i = pos
    while len(args) < count:
        while i < len(text) and text[i] in ' \t':
            i += 1
        if i >= len(text) or text[i] != '"':
            return args if args else None
        i += 1
        buf = []
        while i < len(text) and text[i] != '"':
            c = text[i]
            if c == '\\' and i + 1 < len(text) and text[i + 1] in '"\\$`\n':
                if text[i + 1] != '\n':
                    buf.append(text[i + 1])
                i += 2
                continue
            buf.append(c)
            i += 1
        i += 1
        args.append(''.join(buf))
    return args


def expand_includes(inc):
    """Expand $ac_includes_default; return None if other shell vars remain."""
    inc = inc.replace('$ac_includes_default', INCLUDES_DEFAULT)
    if re.search(r'\$[A-Za-z_{]', inc):
        return None
    return inc


def collect(configure):
    checks = {}  # cachevar -> (kind, subject, includes)

    def add(cachevar, kind, subject, includes):
        checks.setdefault(cachevar, (kind, subject, includes))

    # AC_CHECK_FUNCS_ONCE / AC_CHECK_HEADERS_ONCE lists
    for m in re.finditer(r'as_fn_append ac_func_c_list " (\S+) (\S+)"', configure):
        func = m.group(1)
        add('ac_cv_func_' + func, 'func', func, '')
    for m in re.finditer(r'as_fn_append ac_header_c_list " (\S+) (\S+) (\S+)"', configure):
        add('ac_cv_header_' + m.group(2), 'header', m.group(1), INCLUDES_DEFAULT)

    # Direct calls with literal arguments
    for m in re.finditer(r'ac_fn_c_check_func "\$LINENO" ', configure):
        a = shell_dq_args(configure, m.end(), 2)
        if a and len(a) == 2:
            add(a[1], 'func', a[0], '')
    for m in re.finditer(r'ac_fn_c_check_header_compile "\$LINENO" ', configure):
        a = shell_dq_args(configure, m.end(), 3)
        if a and len(a) == 3:
            inc = expand_includes(a[2])
            if inc is not None:
                add(a[1], 'header', a[0], inc)
    for m in re.finditer(r'ac_fn_check_decl "\$LINENO" ', configure):
        a = shell_dq_args(configure, m.end(), 3)
        if a and len(a) == 3:
            inc = expand_includes(a[2])
            if inc is not None:
                add(a[1], 'decl', a[0], inc)
    for m in re.finditer(r'ac_fn_c_check_type "\$LINENO" ', configure):
        a = shell_dq_args(configure, m.end(), 3)
        if a and len(a) == 3:
            inc = expand_includes(a[2])
            if inc is not None:
                add(a[1], 'type', a[0], inc)
    for m in re.finditer(r'ac_fn_c_check_member "\$LINENO" ', configure):
        a = shell_dq_args(configure, m.end(), 4)
        if a and len(a) == 4:
            inc = expand_includes(a[3])
            if inc is not None:
                add(a[2], 'member', a[0] + '.' + a[1], inc)
    return checks


def program(kind, subject, includes):
    if kind == 'func':
        # AC_CHECK_FUNC style: no header, so only the link step decides.
        # VSI C's default /PREFIX_LIBRARY_ENTRIES maps CRTL names to DECC$.
        return ('#include <limits.h>\n#undef %s\nchar %s (void);\n'
                'int main (void) { return %s (); }\n' % (subject, subject, subject))
    if kind == 'header':
        return '%s#include <%s>\nint main (void) { return 0; }\n' % (includes, subject)
    if kind == 'decl':
        name = subject.split('(')[0].strip()
        return ('%s\nint main (void) {\n#ifndef %s\n  (void) %s;\n#endif\n  return 0; }\n'
                % (includes, name, name))
    if kind == 'type':
        return ('%s\nint main (void) { if (sizeof (%s)) return 0; return 0; }\n'
                % (includes, subject))
    if kind == 'member':
        aggr, member = subject.rsplit('.', 1)
        return ('%s\nint main (void) { static %s ac_aggr; if (sizeof ac_aggr.%s) return 0; return 0; }\n'
                % (includes, aggr, member))
    raise ValueError(kind)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    configure = open(sys.argv[1], encoding='latin-1').read()
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    for f in os.listdir(outdir):
        if f.endswith('.c') or f == 'manifest.txt':
            os.remove(os.path.join(outdir, f))
    checks = collect(configure)
    with open(os.path.join(outdir, 'manifest.txt'), 'w') as man:
        for n, (cachevar, (kind, subject, includes)) in enumerate(sorted(checks.items()), 1):
            pid = 'P%04d' % n
            with open(os.path.join(outdir, pid.lower() + '.c'), 'w') as f:
                f.write(program(kind, subject, includes))
            # manifest: id kind link(Y/N) cachevar subject
            man.write('%s %s %s %s %s\n' % (pid, kind, 'Y' if kind == 'func' else 'N',
                                           cachevar, subject.replace(' ', '_')))
    kinds = {}
    for kind, _, _ in checks.values():
        kinds[kind] = kinds.get(kind, 0) + 1
    print('%d checks: %s' % (len(checks), ', '.join('%s=%d' % kv for kv in sorted(kinds.items()))))


if __name__ == '__main__':
    main()
