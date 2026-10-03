#!/usr/bin/env bash
# prepare.sh - build a VMS-ready source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#   3. run the upstream configure on this host, with every platform answer
#      taken from VMS probe results (probed.site) or hand-settled values
#      (vms-manual.site) instead of from Linux
#   4. generate gnulib's headers and config.h, copy them into the tree
#   5. write the MMS source lists and the configuration snapshot
#
# Nothing in staging/ is ever edited by hand: fix things in patches/ or overlay/.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
tarball=$top/cache/$(basename "$UPSTREAM_URL")
stage=$top/staging/$name
hostcfg=$top/cache/hostcfg-$name
cfgdir=$top/overlay/vms/config
snapshot=$top/snapshot
# Configuration answers come from this node's VSI C run; both architectures
# share one CRTL feature set (see docs/vms-environment.md).
PRIMARY_NODE=${PRIMARY_NODE:-ia64}
PRIMARY_TRIPLET=ia64-hp-openvms

step() { echo "prepare: $*"; }
die() { echo "prepare: error: $*" >&2; exit 1; }

"$top/tools/fetch.sh" >/dev/null

# --- 2. extract, patch, overlay -------------------------------------------
step "extracting $name"
rm -rf "$stage"
mkdir -p "$top/staging"
tar -xJf "$tarball" -C "$top/staging"
[ -d "$stage" ] || die "tarball did not unpack to $stage"

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    step "patch $p"
    patch -d "$stage" -p1 -s --no-backup-if-mismatch -F0 < "$top/patches/$p" ||
        die "patch $p does not apply cleanly"
done < "$top/patches/series"

# overlay/ may only add files; changes to upstream files belong in patches/.
(cd "$top/overlay" && find . -type f) | while read -r f; do
    [ -e "$stage/$f" ] && die "overlay/$f would replace an upstream file; use a patch"
    true
done
cp -a "$top/overlay/." "$stage/"

# --- 3. host configure with VMS answers ----------------------------------
step "configure (host, VMS answers)"
rm -rf "$hostcfg"
mkdir -p "$hostcfg"
site=$hostcfg/vms.site
# Answers: the VSI C configure run (vms_configure.sh) if there is one, else the
# function/header probes; vms-manual.site last so it always wins.
answers=$cfgdir/configure-$PRIMARY_NODE.cache
[ -f "$answers" ] || answers=$cfgdir/probed.site
step "answers from $(basename "$answers")"
python3 "$top/tools/nextheaders_site.py" "$stage/configure" "$cfgdir/crtl_modules.txt" \
    > "$cfgdir/next-headers.site"
cat "$answers" "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$site"
mapfile -t cfgargs < <(grep -v -e '^#' -e '^$' "$cfgdir/configure.args")
# Same --host as vms_configure.sh so configure takes the same code paths.
(cd "$hostcfg" && CONFIG_SITE=$site "$stage/configure" -q -C \
    --build="$("$stage/build-aux/config.guess")" --host=$PRIMARY_TRIPLET CC=gcc "${cfgargs[@]}" \
    > configure.out 2>&1) || { tail -20 "$hostcfg/configure.out"; die "configure failed"; }

# --- 4. generated headers and config.h -------------------------------------
printvar() {  # printvar <dir> <make variable>
    make -s -C "$hostcfg/$1" -f Makefile -f "$top/tools/printvar.mk" "print-$2"
}
built=$(printvar lib BUILT_SOURCES)
step "generating $(echo $built | wc -w) gnulib headers"
make -s -C "$hostcfg/lib" $built >/dev/null
for h in $built; do
    mkdir -p "$stage/lib/$(dirname "$h")"
    cp "$hostcfg/lib/$h" "$stage/lib/$h"
done
# Sources automake generates at build time (grep's colorize.c).
nodist=$(printvar lib nodist_libgreputils_a_SOURCES)
[ -z "$nodist" ] || make -s -C "$hostcfg/lib" $nodist >/dev/null
for f in $nodist; do cp "$hostcfg/lib/$f" "$stage/lib/$f"; done
cp "$hostcfg/config.h" "$stage/config.h"

# --- 5. MMS source lists ---------------------------------------------------
# Objects for libgreputils: automake sources after conditionals, plus LIBOBJS.
lib_srcs=$( { printvar lib libgreputils_a_SOURCES
              echo "$nodist"
              printvar lib libgreputils_a_LIBADD | tr ' ' '\n' | sed -n 's/^libgreputils_a-//; s/\.o$/.c/p'
            } | tr ' ' '\n' | grep '\.c$' | sort -u)
src_srcs=$(printvar src grep_SOURCES | tr ' ' '\n' | grep '\.c$' | sort -u)
dups=$(echo "$lib_srcs" | xargs -n1 basename | sort | uniq -d)
[ -z "$dups" ] || die "duplicate object names in lib: $dups"

mkdir -p "$stage/vms"
echo "$lib_srcs" > "$hostcfg/lib-sources.txt"
echo "$src_srcs" > "$hostcfg/src-sources.txt"
python3 "$top/tools/gen_mms.py" "$cfgdir/ccflags.txt" "$hostcfg/lib-sources.txt" \
    "$hostcfg/src-sources.txt" "$top/overlay/vms/extra-sources.txt" > "$stage/vms/sources.mms"

# --- test suite inputs (run under GNV bash by vms/run_gnv_tests.sh) -------
printvar tests TESTS | tr ' ' '\n' | grep . > "$stage/vms/tests.lst"
# Upstream's own expected failures (XFAIL_TESTS), honoured like 'make check'.
printvar tests XFAIL_TESTS | tr ' ' '\n' | grep . |
    sed 's/$/	upstream XFAIL_TESTS (fails with the included regex matcher on every platform)/' \
    > "$stage/vms/tests-upstream.xfail"
make -s -C "$hostcfg/src" egrep fgrep >/dev/null
for f in egrep fgrep; do
    sed '1s|^#!.*|#!/bin/sh|' "$hostcfg/src/$f" > "$stage/src/$f"
done
printf 'VERSION=%s\nPACKAGE_VERSION=%s\nPACKAGE_BUGREPORT=%s\n' "$UPSTREAM_VERSION" \
    "$UPSTREAM_VERSION" "$(printvar . PACKAGE_BUGREPORT)" > "$stage/vms/tests.env"

# --- PCSI kit inputs (vms/kit/MAKE_KIT.COM builds the kit on each node) ----
: "${KIT_PRODUCER:=ISSINOHO}"
major=${UPSTREAM_VERSION%%.*}; minor=${UPSTREAM_VERSION#*.}; minor=${minor%%.*}
pcsiversion="V$major.$minor-$VMS_PATCH_LEVEL"
kitversion="$UPSTREAM_VERSION-vms$VMS_PATCH_LEVEL"
kit=$stage/vms/kit
subst() {
    sed -e "s/@PRODUCER@/$KIT_PRODUCER/g" -e "s/@BASE@/$1/g" \
        -e "s/@PCSIVERSION@/$pcsiversion/g" -e "s/@VERSION@/$UPSTREAM_VERSION/g" \
        -e "s/@KITVERSION@/$kitversion/g" -e "s/@ARCH@/$2/g"
}
for base in I64VMS X86VMS; do
    subst $base "" < "$kit/grep.pcsi\$desc_template" > "$kit/GREP-$base.PCSI\$DESC"
    subst $base "" < "$kit/grep.pcsi\$text_template" > "$kit/GREP-$base.PCSI\$TEXT"
done
rm -f "$kit/grep.pcsi\$desc_template" "$kit/grep.pcsi\$text_template"
subst "" "IA64 and x86-64" < "$kit/readme.vms" > "$kit/README.VMS"; rm -f "$kit/readme.vms"
make -s -C "$hostcfg/doc" grep.1 >/dev/null
mkdir -p "$kit/doc"
cp "$hostcfg/doc/grep.1" "$kit/doc/GREP.1"
groff -mandoc -Tascii -P-cbou "$hostcfg/doc/grep.1" > "$kit/doc/GREP.TXT" 2>/dev/null
cp "$stage/COPYING" "$kit/doc/COPYING."
cp "$stage/NEWS" "$kit/doc/NEWS."
printf 'KIT_PRODUCER=%s\nPCSI_VERSION=%s\nKIT_VERSION=%s\n' "$KIT_PRODUCER" "$pcsiversion" \
    "$kitversion" > "$kit/kit.env"

# --- snapshot: the resolved configuration, committed and reviewed ----------
mkdir -p "$snapshot"
cp "$hostcfg/config.h" "$snapshot/config.h"
echo "$lib_srcs" > "$snapshot/lib-sources.txt"
echo "$src_srcs" > "$snapshot/src-sources.txt"
# Every cached answer, and where it came from.
cat "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$hostcfg/manual.site"
python3 "$top/tools/cfgreport.py" "$hostcfg/config.cache" "$answers" \
    "$hostcfg/manual.site" > "$snapshot/cache-answers.txt"
step "inherited-from-Linux answers: $(grep -c ' host$' "$snapshot/cache-answers.txt" || true)" \
     "(see snapshot/cache-answers.txt)"

step "staged $stage"
if ! git -C "$top" diff --quiet -- snapshot 2>/dev/null; then
    step "snapshot/ changed - review with: git diff -- snapshot"
fi
