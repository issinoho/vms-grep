#!/bin/sh
# run_gnv_tests.sh - run grep's upstream test suite under GNV bash on OpenVMS.
#
# Started by RUN_GNV_TESTS.COM with the tree's tests/ directory as the
# current directory.  Mirrors the environment that tests/Makefile.am's
# TESTS_ENVIRONMENT provides, runs each test from vms/tests.lst and writes:
#   vms-results.txt   one line per test: PASS|FAIL|SKIP|ERROR|TIMEOUT|EXCLUDED name
#   vms-logs/<t>.log  output of each test that did not pass or skip
# Tests listed in vms/tests.skip (name, then reason) are not run.
#
# Usage: run_gnv_tests.sh [test-name...]     (default: all of vms/tests.lst)

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
PERL=false          # GNV has no perl
LOCALE_FR=none
LOCALE_FR_UTF8=none
PCRE_WORKS=0        # built without PCRE2 for now
MAKE=make
TMPDIR=$abs_srcdir/vms-tmp
PATH=$top/src:$PATH
export VERSION PACKAGE_VERSION PACKAGE_BUGREPORT srcdir top_srcdir abs_srcdir \
       abs_top_srcdir abs_top_builddir built_programs host_triplet CONFIG_HEADER \
       LC_ALL AWK SHELL CC PERL LOCALE_FR LOCALE_FR_UTF8 PCRE_WORKS MAKE TMPDIR PATH

rm -rf vms-tmp vms-logs
mkdir vms-tmp vms-logs
: > vms-results.txt

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
    case $t in
    *.pl)   # upstream runs these with $(PERL); GNV has no perl
        echo "SKIP $t (perl test, no perl in GNV)" | tee -a vms-results.txt
        continue ;;
    esac
    start=$(date +%s)
    GREP_TEST_NAME=$t timeout "$limit" /bin/sh "./$t" > "vms-logs/$t.log" 2>&1
    rc=$?
    case $rc in
    0) status=PASS ;;
    77) status=SKIP ;;
    99) status=ERROR ;;
    124) status=TIMEOUT ;;
    *) status=FAIL ;;
    esac
    case $status in PASS|SKIP) rm -f "vms-logs/$t.log" ;; esac
    echo "$status $t ($(( $(date +%s) - start ))s, rc=$rc)" | tee -a vms-results.txt
done

echo "SUMMARY: $(for s in PASS FAIL SKIP ERROR TIMEOUT EXCLUDED; do
    printf '%s=%s ' $s "$(grep -c "^$s " vms-results.txt)"; done)" | tee -a vms-results.txt
