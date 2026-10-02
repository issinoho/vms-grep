# Plan: GNU grep for OpenVMS (IA64 + x86-64), tracking upstream releases

## Context
VSI's GNV grep is many releases behind. We want a repeatable port that tracks current GNU grep
releases (3.12 today) with minimal maintenance per release. Our repo (`~/projects/vms-grep`, not yet
a git repo) stores **only our deltas**: upstream source is fetched fresh, our patches/new files are
laid over it, VMS headers are generated, and the tree is built natively on IA64 and x86 with MMS.
Outputs: PCSI kits for both architectures. Dependencies (PCRE2 for `-P`, later others) are ported
with the same machinery as separate sibling projects.

Decisions taken:
- Baseline = **signed release tarballs** (`grep-X.Y.tar.xz` + `.sig`), which ship a fully populated
  gnulib `lib/`. `~/projects/grep` (git master, gnulib submodule not initialised) is reference only,
  useful for previewing upcoming changes.
- "configure" equivalent runs on the **Linux host**; VMS only compiles/links/tests/kits.
- VMS access via **ssh + sftp/scp**; GNV bash/coreutils present (for upstream tests); deliver **PCSI kits**.
- PCRE2 is **phase 2** — first release ships with `-P` disabled (grep's no-PCRE stub path).

## Repository layout (`~/projects/vms-grep`)
```
README.md                 how to build / bump version
upstream.conf             UPSTREAM_VERSION=3.12, tarball URL, sha256, GPG key fingerprint
patches/                  quilt-style ordered unified diffs against upstream (series file)
  series
  0001-system-h-vms.patch ...
overlay/                  NEW files only, mirroring tree paths (never whole-file replacements
  vms/                     of upstream files - drift must fail loudly via patch rejects)
    config_vms.h          hand-curated answers to configure tests for VSI C + CRTL
    gl_subst.vms          substitution table for gnulib *.in.h (@HAVE_xxx@, @GNULIB_xxx@, ...)
    vms_crtl_init.c       LIB$INITIALIZE: DECC$ feature logicals (EFS, UNIX filename report,
                          ARGV_PARSE_STYLE, POSIX exit, readdir behaviour, etc.)
    descrip.mms           build lib (gnulib OLB) + src -> GREP.EXE, arch-aware (IA64 / X86_64)
    build.com             wrapper: compiler qualifiers, logicals, invokes MMS
    test_smoke.com        DCL smoke tests (exit status, -i -v -c -r -E -F, case, pipes)
    run_gnv_tests.sh      subset of upstream tests/ under GNV bash, with skip list
    kit/                  PCSI .PCSI$DESC, .PCSI$TEXT, release notes, startup/logicals (GREP$STARTUP.COM,
                          egrep/fgrep foreign-command symbols, DCL$PATH notes)
tools/                    host-side scripts (bash/python)
  fetch.sh                download tarball + sig, verify GPG + sha256 into cache/ (gitignored)
  prepare.sh              extract -> apply patches -> copy overlay -> gen headers -> staging/
  gen_headers.py          *.in.h -> *.h using gl_subst.vms; config.h from config.hin + config_vms.h
  push.sh / remote.sh     sftp staging tree (zip) to node, ssh-run build.com, pull logs/kits back
  nodes.conf              IA64 + x86 hostnames, users, VMS work directories (gitignored or templated)
cache/, staging/, out/    gitignored
```
Same skeleton later reused for `vms-pcre2` (and any other dependency); grep's prepare step consumes
the dependency's installed headers/OLB from a known VMS logical (e.g. `PCRE2$ROOT`).

## Phases

### Phase 0 — Environment discovery (first real work)
- Via ssh, record on each node: VMS version, `CC/VERSION` (IA64 VSI C 7.x vs x86 clang-based VSI C),
  supported `/STANDARD=` levels (C99/C11 matters: gnulib uses `_Noreturn`, `static_assert`,
  `stdckdint.h`, `nullptr` fallbacks), CRTL feature set (`<wchar.h>`, `mbrtowc`, `iconv`, `openat`/
  `fstatat`/`fdopendir` presence, `strtoimax`, `setlocale`/locale support), MMS/MMK, PCSI, GNV version.
- Output: `docs/vms-environment.md` — this drives `config_vms.h` and the substitution table.
- Initialise git repo, `.gitignore`, `upstream.conf`.

### Phase 1 — Host pipeline (no VMS changes yet)
- `fetch.sh`, `prepare.sh`, `gen_headers.py`. First cut of `gen_headers.py` derives the substitution
  list by scanning every `@VAR@` in the tarball's `lib/*.in.h` and `config.hin`, failing on any
  variable missing from `gl_subst.vms` — so new upstream releases surface new configure checks
  explicitly instead of silently.
- Inventory which gnulib modules actually compile into `libgreputils` (from `lib/Makefile.am`/
  `gnulib.mk` in the tarball) to generate the MMS source list rather than hand-maintain it.

### Phase 2 — First native build (iterate, x86 first then IA64)
- Compile gnulib lib into `GREPUTILS.OLB`, then `src/*.c` → `GREP.EXE`, `/NAMES=(AS_IS,SHORTENED)`,
  `/FLOAT=IEEE`, `_POSIX_EXIT`, `_LARGEFILE`, `_USE_STD_STAT`, 64-bit file offsets.
- Expected hot spots, each fixed by a patch or overlay file, never by editing staging/:
  - gnulib replacement headers vs CRTL headers (`#include_next` emulation on VSI C).
  - `fts`/`openat` emulation for `-r` with Unix-style paths; `c-stack` (likely disable/stub).
  - Locale/multibyte (`mbrtoc32`, `uchar.h`) — start with C/UTF-8 behaviour, document limits.
  - File reading: RMS record formats (VAR/VFC vs STREAM_LF), binary-file detection, `-z`.
  - DCL usability: case-preserved argv (`SET PROC/PARSE=EXT` + `DECC$ARGV_PARSE_STYLE`), wildcard
    filename expansion when invoked from DCL, exit status → `$STATUS` mapping documented.
- Keep each fix a separate, described patch so upstreaming to gnulib/grep is possible.

### Phase 3 — Testing
- `test_smoke.com` (DCL, no GNV dependency) — always run, gates kit builds.
- `run_gnv_tests.sh` — upstream `tests/` under GNV bash with an explicit skip list
  (`vms/tests.skip` with reason per test); track pass count per release.

### Phase 4 — Packaging & release
- PCSI kits per arch (`<producer>-I64VMS-GREP-V0312-...` / `X86VMS`), installing to a product root
  with `GREP$STARTUP.COM` defining foreign commands `grep/egrep/fgrep` and/or DCL$PATH.
  Producer prefix to be agreed (not "VSI").
- Also a plain ZIP of the binaries; release notes listing upstream version + our patch level
  (e.g. `3.12-vms1`).

### Phase 5 — PCRE2 dependency, then re-enable `-P`
- New project `vms-pcre2` with identical structure (tarball → patches/overlay → host prepare → MMS).
- Build grep with PCRE2 support against it; kit dependency declared in PCSI.

### Upgrade workflow (per new upstream release)
`upstream.conf` bump → `fetch.sh` → `prepare.sh` (patch rejects + unknown `@VAR@`s are the to-do
list) → `remote.sh build` on both nodes → smoke + GNV tests → kit → tag `vX.Y-vmsN`.

## Verification
- Host: `tools/prepare.sh` produces a staging tree with zero patch rejects and zero unresolved
  `@VAR@` tokens.
- VMS (each arch): `@[.vms]build.com` builds `GREP.EXE` cleanly (warnings logged & reviewed);
  `@[.vms]test_smoke.com` passes; GNV test subset passes at the recorded level.
- `PRODUCT INSTALL` of the kit on a clean node, then `grep --version` reports 3.12 and smoke tests
  pass against the installed image.

## Open items for Phase 0
- Node hostnames/usernames and VMS work directories (`tools/nodes.conf`).
- PCSI producer prefix and install root conventions.
