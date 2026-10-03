# Testing GNU grep on OpenVMS

There are three layers, from quick to thorough:

| Layer | Runs on | Needs | Command (host) |
|---|---|---|---|
| DCL smoke test, 18 checks | IA64, x86-64 | nothing extra | `tools/test.sh <node>` |
| Regex tables, 329 cases | IA64, x86-64 | VSI Perl | `@[.VMS]REGEX_TESTS` on the node |
| Upstream test suite, 128 tests | x86-64 | GNV (bash 4.4 + coreutils), VSI Perl | `tools/gnvtest.sh x86` |

## DCL smoke test (`vms/test_smoke.com`)
Basic options, exit statuses as seen by DCL, `-r` over a directory tree, case preservation
under `SET PROCESS/PARSE_STYLE=EXTENDED`, and output to a record-oriented destination: a DCL
`PIPE` into `SEARCH` must see each line as a single record. It gates every build, and it
also runs against an installed kit (`@[.VMS]TEST_SMOKE GREP$ROOT:[BIN]GREP.EXE`).

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
SKIP (with upstream's reason), ERROR, KILLED or EXCLUDED per test, and logs of failures
in `out/gnvtests-x86/logs/`.

GNV's `timeout` behaves badly on VMS. When it fires inside a batch job it kills the
whole process tree, including the runner. So the runner applies no timeout of its own,
and if a test leaves no result line, the DCL loop records it as KILLED. A killed test on
an expected-failure list counts as XFAIL; `glibc-infloop` is expected to loop until its
timeout fires.

Expected failures come from two lists:
- `vms/tests-upstream.xfail`, generated from upstream's own `XFAIL_TESTS`
  (`triple-backref`, `glibc-infloop` and `equiv-classes`, which fail with the included
  regex matcher on every platform);
- `vms/tests.xfail`, for VMS/GNV environment problems.

### Test-only patches (environment, not grep)
| Patch | Why |
|---|---|
| 0004 | GNV bash gives a shell function run inside a pipeline the wrong arguments; `init.cfg`'s `tr` wrapper broke every `... \| tr` test. |
| 0005 | VMS pipes have no SIGPIPE, so `yes \| head` never ends; use a finite `seq \| sed`. |
| 0008 | `require_timeout_` expects `timeout 0.01 sleep 0.02` to fire. Creating a process takes far longer than 10 ms on VMS, and a firing timeout kills the shells in a batch job, so on VMS the check only confirms that `timeout 10 true` runs. |

### Not run (`vms/tests.skip`)
| Test | Reason |
|---|---|
| max-count-overread | Needs an endless producer (`yes \| grep -m1`); `yes` never sees SIGPIPE. |
| yesno | Needs file offsets shared between processes (`{ grep; sed; } < file`); each VMS process opens the file separately. |
| skip-device | Needs `mkfifo`; VMS has no FIFOs. Its stdin checks pass before set-up fails. |
| hash-collision-perf | Sized by child CPU time, which VMS Perl reports as 0; it escalates to 640,000 patterns and runs for hours. |
| grep-dev-null-out | Needs an endless producer (`awk` loop) and a timeout that fires. |
| mb-non-UTF8-perf-Fw | Performance test: builds 10 million lines through a GNV pipe (hours) and relies on a 30-second timeout. |

### Expected failures (`vms/tests.xfail`)
| Test | Reason |
|---|---|
| fedora | One sub-check: GNV bash drops the empty argument in `grep -Fw ""`, and `returns_` runs inside a pipeline. |
| euc-mb | It pipes into its own shell functions, which GNV runs with the wrong arguments. The same four EUC-JP checks pass when run natively from VSI Perl. |
| backref-multibyte-slow | It sets its time limit by timing `grep` run from Perl, which on VMS goes to DCL rather than our grep. Measured natively, the UTF-8 case takes 0.14 s against 0.12 s in the C locale. |

## Current results (grep 3.12)
| Suite | IA64 | x86-64 |
|---|---|---|
| DCL smoke test | 18/18 | 18/18 |
| Regex tables | 329/329 | 329/329 |
| Upstream suite | (no usable GNV) | 84 pass, 0 unexpected failures, 6 expected failures, 32 skipped (14 PCRE, 7 "expensive", the rest missing locales or devices), 6 excluded |

The skips break down as follows. PCRE waits for the PCRE2 port. The "expensive" tests are
skipped upstream unless `RUN_EXPENSIVE_TESTS=yes`. The locales VMS doesn't ship are
`tr_TR.UTF-8`, `cs_CZ.UTF-8`, `ru_RU.KOI8-R` and `zh_HK.big5hkscs`. VMS also has no
`/dev/full` and no `/proc`.

### GNV and VMS limits found along the way
- An **empty argument** (`""`) is dropped when GNV bash starts a VMS image; from DCL it
  arrives intact.
- **Upper-case options** are lower-cased under the default `PARSE_STYLE=TRADITIONAL`
  (`-E` arrives as `-e`). Use `SET PROCESS/PARSE_STYLE=EXTENDED` or quote them.
- **Locales:** the CRTL's `setlocale(LC_ALL, "")` reads only logical names, never
  environment variables; patch 0006 makes grep honour both. Its UTF-8 decoder accepts
  surrogates and rejects U+10FFFF; patch 0007 corrects both. IA64 has only the `UTF8-20`
  locale (`MB_CUR_MAX` 3), so it cannot handle 4-byte characters.
