# VMS build environment

Collected by `tools/vms_probe.com` and `tools/vms_crtl_probe.com` (raw logs in `cache/`).

## Access notes (all nodes)
- ssh/sftp with key `~/.ssh/vms_ed25519` (VSI OpenSSH 9.9).
- Capturing stdout from `ssh host <cmd>` is unreliable (output sometimes lost; `PIPE ... ; WAIT` hangs).
  Instead, run procedures with `@X.COM/OUTPUT=<log>` and fetch the log with sftp.
- `SYS$LOGIN:[.SUB]` is invalid here (SYS$LOGIN is not a rooted logical). Use
  `DISK$USER:[USERNAME.VMS_GREP]`. sftp sees it as `/DISK$USER/username/vms_grep` (ODS-5, case preserved).
- Output uses CRLF line endings; strip `\r` on the host side.
- **`WAIT` hangs** in a DCL session started by `ssh host <cmd>`; never use it there (batch jobs are fine).
- Each sftp session costs ~1.2 s even over a multiplexed connection (VMS starts an sftp server
  process per session). `tools/vms.sh` wraps all of the above.
- Batch jobs default to `/LIST` and `/MAP`; pass `/NOLIST` and `/NOMAP` explicitly.
- MYI64 `SYS$BATCH` job limit raised to 4 (2026-10-02), so a compile server and builds can run together.
- GNV: neither node runs GNV$STARTUP at boot. `[.VMS]GNV_ENV.COM` defines GNU/SYS$POSIX_ROOT per process.
  x86 GNV (rooted at `[GNV.X86.]`) has bash 4.4 + coreutils and runs the upstream suite; IA64 GNV (2015, bash 1.14.8,
  no `timeout`/`printf`) cannot.
- A DCL procedure's `DEFINE/USER SYS$OUTPUT file` creates no file when nothing is written.

## IA64 — MYI64 (<ia64-host>)
| Item | Value |
|---|---|
| Hardware | HP rx2660 (bare metal) |
| OS | OpenVMS IA64 V8.4-2L3 |
| C compiler | VSI C V7.4-001 (`/STANDARD=C99` and `LATEST` accepted; C99 is the ceiling) |
| MMS | V4.0-5 (no MMK) |
| GNV | V3.0-2 installed, but no `GNV$*` logicals defined in the probe session |
| Other | GIT 2.44, CURL 8.13, OpenSSL 3.x, `DCL$PATH = DKA800:[TOOLS]` |
| Parse style | Traditional (default) |

### Language features (VSI C 7.4)
- Supported: C99 (VLAs, designated initialisers, `_Bool`, `inline`, `__func__`), variadic macros, `__typeof__`.
- **Not supported**: `_Static_assert`, `_Noreturn`, `__attribute__`, `#include_next` (warning, then ignored),
  `__builtin_*_overflow`.
- **Missing headers**: `stdalign.h`, `stdnoreturn.h`, `stdckdint.h`, `uchar.h`, `threads.h`,
  `fnmatch.h`, `getopt.h`, `libintl.h`, `spawn.h`, `sys/select.h`.

### CRTL functions
- **Present**: iconv, mbrtowc/mbrlen/mbsinit/btowc/wcrtomb/wcwidth, iswctype/towlower, setlocale,
  nl_langinfo, strtoimax/strtoumax, strtoll, getpagesize, isblank, mempcpy, stpcpy, strnlen, strndup,
  strerror_r, lstat, readlink, realpath, fseeko/ftello, getdelim, snprintf, asprintf, sigaction,
  clock_gettime, nanosleep, alarm, pipe, fcntl.
- **Missing**: openat, fstatat, fdopendir, dirfd, fchdir, unlinkat, memrchr, reallocarray,
  sigaltstack, newlocale/locale_t, c32rtomb (uchar), fnmatch, getopt_long, `__fpending`;
  `RLIMIT_STACK` not defined.

### Implications for the port
- gnulib's C11/C23 assumptions (`static_assert`, `_Noreturn`, attributes, `stdckdint.h`) must come
  from gnulib fallbacks selected by our generated headers/config, or small shims. IA64 is the
  tighter target; any shim needed there is the baseline.
- No `#include_next`: generated gnulib wrapper headers must reach the CRTL's own header by another
  route (decided in Phase 1).
- `-r` (fts) depends on the `*at` functions and `fchdir`, all missing: biggest functional risk on IA64.
- `c-stack` needs `sigaltstack`: stub it out.

## x86-64 — X86VMS (<x86-host>, non-default ssh port)
| Item | Value |
|---|---|
| Hardware | KVM/QEMU guest (Q35 + ICH9) on a Debian NUC — slower; timings not representative |
| OS | OpenVMS x86_64 E9.2-4 |
| C compiler | VSI C x86-64 V7.7-003 (GEM back end, *not* clang) |
| MMS | V4.0-5 (no MMK) |
| GNV | V3.0-2F |
| Other | Python 3.10, Perl 5.42, GIT 2.44, CURL 8.13, CXX 10.1 |

The language-feature and CRTL probe results are **identical to IA64**, line for line. One set of
configuration answers serves both architectures; the per-arch differences are compiler/link qualifiers only.

Type sizes (default qualifiers + `_LARGEFILE`): `long`=4, pointer=4, `size_t`=4, `wchar_t`=4, `off_t`=8.

Notes:
- The CRTL probe is slow on this node; run long jobs with `SUBMIT` (batch queue `X86VMS_BATCH`) and poll for the log.
- In DCL loops, `F$SEARCH` calls without a stream id share one wildcard context; use stream ids.
- Home directory protection must not allow group/world write, or sshd ignores `authorized_keys`.

### clang on x86 (from the C++ kit)
VSI C++ V10.1-3U1 ships `SYS$SYSTEM:CLANG.EXE` (clang 10.0.1, target x86_64-OpenVMS). No DCL verb is
defined, so it is used as a foreign command: `clang :== $SYS$SYSTEM:CLANG.EXE`. It compiles **C** (`-x c -std=c11`):
`_Static_assert`, `_Noreturn`, `__attribute__` and `__builtin_add_overflow` all work, and the objects
link and run with the standard CRTL. IA64 has no equivalent, so VSI C remains the baseline compiler for both.

### C++ on IA64
VSI C++ V7.4-006 is installed. It is the classic EDG-based compiler, not clang: there is no `CLANG.EXE`, and it
rejects C++11 `static_assert`. It gives no help with the C11 gaps; VSI C stays the IA64 compiler.

## Command-line case (affects users)
With the default `PARSE_STYLE=TRADITIONAL`, DCL upper-cases an unquoted command line and the
CRTL then lower-cases `argv`, so `grep -E x` reaches grep as `grep -e x`. Upper-case options and
mixed-case patterns therefore need either `SET PROCESS/PARSE_STYLE=EXTENDED` (grep sets
`DECC$ARGV_PARSE_STYLE`, so case is then preserved) or double quotes (`grep "-E" "Foo"`).
The case is lost before grep starts, so grep itself cannot correct it. This must go in the user docs.
