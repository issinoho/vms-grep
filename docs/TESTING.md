# Testing GNU grep on OpenVMS

There are three layers, from quick to thorough:

| Layer | Runs on | Needs | Command (host) |
|---|---|---|---|
| DCL smoke test, 16 checks | IA64, x86-64 | nothing extra | `tools/test.sh <node>` |
| Regex tables, 329 cases | IA64, x86-64 | VSI Perl | `@[.VMS]REGEX_TESTS` on the node |
| Upstream test suite, 128 tests | x86-64 | GNV (bash 4.4 + coreutils), VSI Perl | `tools/gnvtest.sh x86` |

## DCL smoke test (`vms/test_smoke.com`)
Basic options, exit statuses as seen by DCL, `-r` over a directory tree, and case
preservation under `SET PROCESS/PARSE_STYLE=EXTENDED`. It gates every build.

## Regex tables (`vms/regex_tests.pl`, `vms/regex_tests.com`)
These are upstream's `bre.tests`, `ere.tests` and `spencer1.tests`, the tables that
`bre.awk`/`ere.awk`/`spencer1.awk` normally turn into shell scripts. Each case runs
directly from VSI Perl, with the pattern and input passed through files (`grep -f`), so
no GNV is involved. This is IA64's main correctness coverage: IA64's GNV is from 2015
(bash 1.14) and cannot run gnulib's `init.sh`.

## Upstream suite under GNV (`vms/run_gnv_tests.sh`, `vms/run_gnv_tests.com`)
This mirrors `tests/Makefile.am`'s `TESTS_ENVIRONMENT`. It runs `.pl` tests under VSI Perl
and the rest under `/bin/sh`, starting a fresh bash for each test. A long-lived GNV bash
exhausts the subprocess quota (10) with children that tests leave behind, and the batch
job then dies silently. The procedure also:
- defines GNV's root logical names per process (`vms/gnv_env.com`), including `BIN` →
  `GNU:[BIN]`, so that `/bin/sh` resolves;
- builds the `get-mb-cur-max` helper;
- aliases `en_US.UTF-8`, `fr_FR.UTF-8` and `ja_JP.EUC-JP`, which VMS does not ship under
  those names, in a private locale directory that it puts first in this process's
  `SYS$I18N_LOCALE` search list.

Results land in `out/gnvtests-x86/results.txt`, as one of PASS, FAIL, XFAIL, XPASS,
SKIP (with upstream's reason), ERROR, TIMEOUT or EXCLUDED per test, and logs of failures
in `out/gnvtests-x86/logs/`.

### Test-only patches (environment, not grep)
| Patch | Why |
|---|---|
| 0004 | GNV bash gives a shell function run inside a pipeline the wrong arguments; `init.cfg`'s `tr` wrapper broke every `... \| tr` test. |
| 0005 | VMS pipes have no SIGPIPE, so `yes \| head` never ends; use a finite `seq \| sed`. |
| 0008 | Creating a process takes far longer than 10 ms, so `require_timeout_`'s `timeout 0.01 sleep 0.02` check is replaced by a whole-second one. |

### Not run (`vms/tests.skip`)
| Test | Reason |
|---|---|
| max-count-overread | Needs an endless producer (`yes \| grep -m1`); `yes` never sees SIGPIPE. |
| yesno | Needs file offsets shared between processes (`{ grep; sed; } < file`); each VMS process opens the file separately. |

### Expected failures (`vms/tests.xfail`)
| Test | Reason |
|---|---|
| fedora | One sub-check: GNV bash drops the empty argument in `grep -Fw ""`, and `returns_` runs inside a pipeline. |
| equiv-classes | `[[=a=]]` matching accented letters needs glibc's collation data; elsewhere gnulib treats it as `[a]`. |

### GNV and VMS limits found along the way
- An **empty argument** (`""`) is dropped when GNV bash starts a VMS image; from DCL it
  arrives intact.
- **Upper-case options** are lower-cased under the default `PARSE_STYLE=TRADITIONAL`
  (`-E` arrives as `-e`). Use `SET PROCESS/PARSE_STYLE=EXTENDED` or quote them.
- **Locales:** the CRTL's `setlocale(LC_ALL, "")` reads only logical names, never
  environment variables; patch 0006 makes grep honour both. Its UTF-8 decoder accepts
  surrogates and rejects U+10FFFF; patch 0007 corrects both. IA64 has only the `UTF8-20`
  locale (`MB_CUR_MAX` 3), so it cannot handle 4-byte characters.
