# GNU grep for OpenVMS

A port of current GNU grep to OpenVMS on **IA64** and **x86-64**, kept as a thin layer
over the official GNU release so that it can follow upstream releases with minimal effort.
VSI's GNV kit ships a grep that is many releases behind; this port starts from
**GNU grep 3.12**.

This repository holds **only our changes**. Upstream source is never stored here: every
build starts from the signed release tarball, applies our patches, adds our VMS-only
files, and generates the configuration for VSI C.

## Status

| | IA64 (OpenVMS V8.4-2L3, VSI C 7.4) | x86-64 (OpenVMS E9.2-4, VSI C 7.7) |
|---|---|---|
| Builds with MMS | yes | yes |
| DCL smoke test | 18/18 | 18/18 |
| Regex tables (BRE, ERE, Spencer) | 329/329 | 329/329 |
| Upstream test suite (128 tests) | not runnable (GNV too old) | 84 pass, 0 unexpected failures |
| `grep -P` (PCRE2) | not yet | not yet |
| PCSI kit ([v3.12-vms1](https://github.com/issinoho/vms-grep/releases/tag/v3.12-vms1)) | `ISSINOHO-I64VMS-GREP-V0312-1-1.PCSI` | `ISSINOHO-X86VMS-GREP-V0312-1-1.PCSI` |

See [docs/TESTING.md](docs/TESTING.md) for the details of every skipped, excluded and
expected-to-fail test.

## Installing the kit

Download the kits from the
[latest release](https://github.com/issinoho/vms-grep/releases/latest); the current
release is [v3.12-vms1](https://github.com/issinoho/vms-grep/releases/tag/v3.12-vms1).
Check them against the release's `SHA256SUMS`. The kits are PCSI files, named `ISSINOHO-<base>-GREP-V0312-1-1.PCSI` (grep 3.12, VMS patch
level 1). A kit downloaded through a non-VMS system arrives without its record format,
so restore that first, then install it:

```
$ SET FILE/ATTRIBUTE=(RFM:FIX,LRL:8192,MRS:8192,RAT:NONE) ISSINOHO-*-GREP-V0312-1-1.PCSI
$ PRODUCT INSTALL GREP /PRODUCER=ISSINOHO /SOURCE=dev:[dir]
```

The kits have been tested by installing, verifying and removing them on both architectures.
They are not signed, so PCSI notes that it cannot validate a signature. It installs
`[GREP.BIN]GREP.EXE`, the documentation in `[GREP.DOC]` (`README.VMS`, a plain-text
manual `GREP.TXT`, `GREP.1`, `NEWS`, `COPYING`) and two procedures:

- `[GREP]GREP$STARTUP.COM` defines `GREP$ROOT`. It runs once at installation; to run it at
  every boot, add it to `SYS$MANAGER:SYSTARTUP_VMS.COM`.
- `[GREP]GREP$SETUP.COM` defines `grep`, `egrep` and `fgrep` for a user (add it to
  `LOGIN.COM`): `$ @GREP$ROOT:[000000]GREP$SETUP.COM`.

Removing the product (`PRODUCT REMOVE GREP`) deassigns `GREP$ROOT`.

## Using grep on OpenVMS

These notes are for people running the resulting `GREP.EXE`:

- **Defining the command:** define it as a foreign command, `$ grep :== $dev:[dir]GREP.EXE`,
  or put the directory in `DCL$PATH`.
- **Case of options and patterns:** under the default `PARSE_STYLE=TRADITIONAL`, DCL
  upper-cases the command line and the C runtime then lower-cases it, so `grep -E Foo`
  arrives as `grep -e foo`. Use `$ SET PROCESS/PARSE_STYLE=EXTENDED` (grep then preserves
  case), or quote the arguments: `grep "-E" "Foo"`.
- **Exit status:** grep returns POSIX exit codes (0 = match, 1 = no match, 2 = error),
  encoded in `$STATUS` as C-facility values. In DCL, `($STATUS .AND. %X7F8) / 8` gives the
  code.
- **File names:** these are reported in Unix form (`dir/file.txt`). `-r` recurses through
  directories.
- **Locales:** set a locale with a logical name or an environment variable, for example
  `$ DEFINE LC_ALL "UTF8-20"`, or `LC_ALL=ja_JP.UTF-8` under GNV bash. VMS has no
  `en_US.UTF-8`; use the generic `UTF8-xx` locales. IA64 ships only `UTF8-20`
  (at most 3-byte characters).
- **Overriding the C runtime switches:** grep sets several of these at start-up (Unix file
  names, case preservation, …; see `overlay/vms/vms_crtl_init.c`). Defining the
  corresponding `DECC$` logical name yourself overrides grep's choice.

## Repository layout

```
upstream.conf          upstream version, tarball URL, SHA-256, signing key
patches/               unified diffs against the upstream tree, applied in order (series)
overlay/               new files only, copied into the tree (never replaces upstream files)
  vms/                 DESCRIP.MMS, BUILD.COM, VMS C sources, test procedures
  vms/config/          configure answers for VSI C (generated + hand-settled), compiler flags
tools/                 host-side scripts: fetch, prepare, push, configure, build, test
snapshot/              resolved config.h, source lists, every configure answer (reviewed)
probes/                raw logs of the VMS function/header probes
docs/                  plan, VMS environment findings, testing
cache/ staging/ out/   generated locally, not committed
```

## Patches

| Patch | Purpose |
|---|---|
| 0001 | `assert.h`: redefine `assert` on each inclusion. The CRTL header is include-guarded. |
| 0002 | `getprogname`: VMS implementation using `JPI$_IMAGNAME`. |
| 0003 | `open`: the CRTL cannot `open()` a directory (ENOENT); use gnulib's dummy-descriptor fallback. Makes `-r` work. |
| 0004 | tests: no `tr()` shell function on VMS (GNV bash mangles function arguments in pipelines). |
| 0005 | tests: finite producers instead of `yes \| head` (no SIGPIPE on VMS pipes). |
| 0006 | grep: also take `LC_ALL`/`LC_*`/`LANG` from environment variables (the CRTL reads only logical names). |
| 0007 | `mbrtowc`: correct the CRTL's UTF-8 decoding (accepts surrogates, rejects U+10FFFF). |
| 0008 | tests: a whole-second `timeout` capability check on VMS. |
| 0009 | grep: write output with `putc` on VMS. For record-oriented stdout (terminal, log file, mailbox) the CRTL turns each `fwrite` item into a record, so lines came out one character per line. |

Patches 0004, 0005 and 0008 change only the test suite.

## Requirements

- **Linux host:** bash, python3, gcc and make (for the host-side `configure` run), curl,
  gpg, and ssh/sftp.
- **VMS nodes:** VSI C, MMS and OpenSSH. Testing also uses VSI Perl and, on x86-64, GNV
  (bash 4.4 and coreutils).

## First-time setup

1. Create an ssh key with no passphrase for automation, e.g. `~/.ssh/vms_ed25519` (or point
   `VMS_SSH_KEY` at another key). Install its public key in `SYS$LOGIN:[.SSH]AUTHORIZED_KEYS.`
   on each node. The login directory must not be group- or world-writable, or sshd ignores
   the key.
2. Copy `tools/nodes.conf.example` to `tools/nodes.conf` and fill in each node: host, port,
   user, VMS work directory and the matching sftp path. This file is git-ignored.
3. Create the work directory on each node, e.g. `$ CREATE/DIRECTORY DISK$USER:[USERNAME.VMS_GREP]`.
4. Check access: `tools/vms.sh ia64 dcl 'show time'`.

## Everyday workflow

```sh
tools/prepare.sh            # fetch + verify tarball, patch, overlay, generate headers -> staging/
tools/build.sh ia64         # push changed files, MMS build on the node -> [.BIN_IA64]GREP.EXE
tools/test.sh ia64          # DCL smoke test against the built image
tools/build.sh x86 && tools/test.sh x86
tools/gnvtest.sh x86        # full upstream test suite under GNV (about 90 minutes)
tools/kit.sh ia64           # PCSI kit -> out/kits/ (likewise x86)
```

- `tools/build.sh <node> ALL KEEP_GOING` compiles everything, including files after the
  first failure, so one run reports every error.
- `tools/build.sh <node> CLEAN` removes the objects. MMS does not track changes to compiler
  flags, so clean after changing them.
- `tools/push.sh` uploads only files whose content changed, so MMS rebuilds only what's affected.
- On a node, `@[.VMS]REGEX_TESTS` runs the regex tables with VSI Perl; it needs no GNV.

## Tools

| Script | What it does |
|---|---|
| `tools/fetch.sh` | Downloads the tarball and verifies its SHA-256 and GPG signature (GNU keyring). |
| `tools/prepare.sh` | Builds `staging/<name>-<version>`: patches, overlay, offline `configure`, headers, MMS rules, snapshot. |
| `tools/push.sh <node>` | Uploads the prepared tree (changed files only). |
| `tools/build.sh <node> [target] [KEEP_GOING]` | Pushes, then runs `[.VMS]BUILD.COM`. |
| `tools/test.sh <node>` | Runs `[.VMS]TEST_SMOKE.COM`. |
| `tools/gnvtest.sh <node> [test...]` | Runs the upstream suite in batch and fetches results to `out/gnvtests-<node>/`. |
| `tools/kit.sh <node>` | Builds, then makes the PCSI kit on the node (`[.VMS.KIT]MAKE_KIT.COM`) and fetches it to `out/kits/`. |
| `tools/vms_configure.sh <node>` | Runs upstream `configure` with VSI C on the node as the compiler (once per release). |
| `tools/vms.sh <node> dcl\|run\|batch\|put\|get …` | Reliable remote execution and file transfer (see below). |

`tools/vms.sh` exists because output from `ssh host <command>` is unreliable on these
systems, and sessions sometimes never close. Every remote step writes a log and a
completion marker, which are fetched with sftp.

## How configuration works

GNU `configure` cannot run usefully on VMS, so it runs on the Linux host with VMS answers:

1. `tools/vms_configure.sh <node>` runs upstream `configure` in cross mode with
   `tools/vmscc` as the compiler. Every compile, link and preprocessor test is sent to
   `vms_ccserver.com` on the node and judged by VSI C; results are memoised by content
   hash. It takes 50–70 minutes, once per upstream release, and writes
   `overlay/vms/config/configure-<node>.cache` (committed). The IA64 and x86-64 answers are
   identical apart from the CPU name.
2. `overlay/vms/config/vms-manual.site` holds hand-settled answers, each with a reason:
   run-time behaviour that cross mode cannot test, and CRTL quirks.
3. `overlay/vms/config/next-headers.site` (generated) maps gnulib's wrapper headers to
   CRTL text-library modules. VSI C has no `#include_next`, so gnulib's `lib/stdio.h` uses
   `#include STDIO`, which VSI C reads from `SYS$LIBRARY:DECC$RTLDEF.TLB`.
4. `tools/prepare.sh` replays these answers through the host `configure` offline. It
   generates `config.h`, the gnulib headers and `vms/sources.mms`, and records the result
   in `snapshot/`. Review `git diff -- snapshot` whenever it changes.

## Moving to a new upstream release

1. Update `upstream.conf` (version, URL, SHA-256).
2. Run `tools/prepare.sh`. Patch rejects are the first to-do list; refresh the affected patches.
3. Run `tools/vms_configure.sh ia64` (and `x86`) to refresh the answers, and compare the two
   cache files.
4. Run `tools/prepare.sh` again, then review `git diff -- snapshot`.
5. Build and test on both nodes (smoke test, regex tables, `tools/gnvtest.sh x86`), then fix
   anything new with a patch or an overlay file.

## Layout of a prepared tree on VMS

```
[.GREP-3_12]                config.h, lib/, src/, tests/, vms/
[.GREP-3_12.VMS]            BUILD.COM, DESCRIP.MMS, SOURCES.MMS, test procedures, VMS sources
[.GREP-3_12.OBJ_<arch>]     grep objects, GREPUTILS.OLB, link map
[.GREP-3_12.OBJ_<arch>.LIB] gnulib objects
[.GREP-3_12.BIN_<arch>]     GREP.EXE
```

## Roadmap

1. Port PCRE2 with the same structure, then enable `grep -P`.
2. VMS-specific behaviour: native record formats (VAR/VFC files), wildcard file
   specifications typed at DCL, and a review of the compiler's warnings.

## Further reading

- [docs/PLAN.md](docs/PLAN.md): the overall plan and decisions.
- [docs/vms-environment.md](docs/vms-environment.md): toolchain, CRTL and GNV findings, and
  operational quirks of the nodes.
- [docs/TESTING.md](docs/TESTING.md): the test layers, results and every exception with
  its reason.

## Licence

GNU grep and gnulib are licensed under the GNU General Public License, version 3 or later.
The patches and the VMS build files in this repository are distributed under the same
terms; see `COPYING`.
