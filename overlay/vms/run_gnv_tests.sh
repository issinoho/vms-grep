#!/bin/sh
# run_gnv_tests.sh - run grep's upstream test suite under GNV bash on OpenVMS.
#
# Started by RUN_GNV_TESTS.COM with the tree's tests/ directory as the
# current directory.  Mirrors the environment that tests/Makefile.am's
# TESTS_ENVIRONMENT provides, runs tests and writes:
#   vms-results.txt   one line per test:
#                     PASS|FAIL|XFAIL|XPASS|SKIP|ERROR|TIMEOUT|EXCLUDED name (detail)
#   vms-logs/<t>.log  output of each test that did not pass or skip
# Tests listed in vms/tests.skip (name, then reason) are not run.  Tests in
# vms/tests.xfail (name, then reason) run, but a failure is expected there
# (XFAIL) because of the GNV environment rather than grep; a pass is XPASS.
#
# Usage: run_gnv_tests.sh [test-name...]            fresh results (default: all tests)
#        run_gnv_tests.sh --append test-name...     add to existing results
#        run_gnv_tests.sh --summary                 append the summary line
# RUN_GNV_TESTS.COM runs the whole suite as one --append call per test: a
# long-lived GNV bash eventually exhausts the subprocess quota with children
# that tests leave behind, and a fresh bash per test avoids that.

top=$(cd .. && pwd)
. "$top/vms/tests.env"

srcdir=.
top_srcdir=..
abs_srcdir=$(pwd)
abs_top_srcdir=$top
abs_top_builddir=$top
built_programs='grep egrep fgrep'
host_triplet=$(uname -m)-hp-openvms
CONFIG_HEADER=$top/config.h
LC_ALL=C
AWK=awk
SHELL=/bin/sh
CC=false            # no host C compiler for tests that build helpers
# VSI Perl, made reachable by RUN_GNV_TESTS.COM (PERL_ROOT); else no perl.
if [ -f /perl_root/perl.exe ]; then PERL=/perl_root/perl; else PERL=false; fi
# fr_FR.ISO8859-1 ships with VMS; fr_FR.UTF-8 is aliased by RUN_GNV_TESTS.COM.
LOCALE_FR=fr_FR.ISO8859-1
LOCALE_FR_UTF8=fr_FR.UTF-8
PCRE_WORKS=0        # built without PCRE2 for now
MAKE=make
TMPDIR=$abs_srcdir/vms-tmp
PATH=$top/src:$PATH
export VERSION PACKAGE_VERSION PACKAGE_BUGREPORT srcdir top_srcdir abs_srcdir \
       abs_top_srcdir abs_top_builddir built_programs host_triplet CONFIG_HEADER \
       LC_ALL AWK SHELL CC PERL LOCALE_FR LOCALE_FR_UTF8 PCRE_WORKS MAKE TMPDIR PATH

summary() {
    line="SUMMARY:"
    for s in PASS FAIL XFAIL XPASS SKIP ERROR TIMEOUT EXCLUDED; do
        line="$line $s=$(grep -c "^$s " vms-results.txt)"
    done
    echo "$line" | tee -a vms-results.txt
}

want_summary=
case ${1:-} in
--summary) summary; exit 0 ;;
--append) shift ;;
*) rm -rf vms-tmp vms-logs; : > vms-results.txt; want_summary=1 ;;
esac
mkdir -p vms-tmp vms-logs

if [ $# -gt 0 ]; then
    tests=$(echo "$*" | tr A-Z a-z)   # DCL upper-cases its arguments
else
    tests=$(cat "$top/vms/tests.lst")
fi

limit=${GREP_TEST_TIMEOUT:-900}
for t in $tests; do
    reason=$(sed -n "s/^$t[ 	][ 	]*//p" "$top/vms/tests.skip" 2>/dev/null)
    if [ -n "$reason" ]; then
        echo "EXCLUDED $t ($reason)" | tee -a vms-results.txt
        continue
    fi
    # As tests/Makefile.am: .pl tests run under perl, the rest under sh.
    case $t in
    *.pl)
        if [ "$PERL" = false ]; then
            echo "SKIP $t (perl test, no perl available)" | tee -a vms-results.txt
            continue
        fi
        set -- "$PERL" -w -I. -MCoreutils -MCuSkip "-MCuTmpdir qw($t)" ;;
    *)  set -- /bin/sh ;;
    esac
    start=$(date +%s)
    GREP_TEST_NAME=$t timeout "$limit" "$@" "./$t" > "vms-logs/$t.log" 2>&1
    rc=$?
    case $rc in
    0) status=PASS ;;
    77) status=SKIP ;;
    99) status=ERROR ;;
    124) status=TIMEOUT ;;
    *) status=FAIL ;;
    esac
    detail="$(( $(date +%s) - start ))s, rc=$rc"
    xfail=$(sed -n "s/^$t[ 	][ 	]*//p" "$top/vms/tests.xfail" 2>/dev/null)
    if [ -n "$xfail" ]; then
        case $status in FAIL) status=XFAIL; detail="$detail; $xfail" ;; PASS) status=XPASS ;; esac
    fi
    if [ $status = SKIP ]; then
        why=$(sed -n 's/.*skipped test: //p' "vms-logs/$t.log" | head -1)
        detail="$detail; ${why:-no reason given}"
    fi
    case $status in PASS|SKIP) rm -f "vms-logs/$t.log" ;; esac
    echo "$status $t ($detail)" | tee -a vms-results.txt
done

[ -n "$want_summary" ] && summary
exit 0
