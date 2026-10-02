# GNU grep for OpenVMS

A port of current GNU grep to OpenVMS IA64 and x86-64, kept as a thin layer over
the official GNU release. This repository holds **only our changes**:

- `patches/` holds unified diffs against the upstream tree, applied in the order listed in `series`.
- `overlay/` holds new files only: the VMS build (`vms/`) and configuration answers (`vms/config/`).
- `tools/` holds the host-side scripts that fetch, prepare, push, configure, build and test.

Upstream source is never stored here. Each step starts from the signed release tarball.

## Requirements

- **Linux host:** bash, python3, gcc and make (for the host-side `configure` run), curl, gpg,
  and ssh/sftp access to the VMS nodes.
- **VMS nodes:** VSI C, MMS, OpenSSH. Set them up in `tools/nodes.conf`
  (copy it from `tools/nodes.conf.example`). Authentication uses the key in `~/.ssh/vms_ed25519`.

## Everyday workflow

```sh
tools/prepare.sh            # fetch + verify tarball, patch, overlay, generate headers -> staging/
tools/build.sh ia64         # push changed files, MMS build on the node -> [.BIN_IA64]GREP.EXE
tools/test.sh ia64          # DCL smoke test against the built image
tools/build.sh x86 && tools/test.sh x86
```

`tools/build.sh <node> ALL KEEP_GOING` compiles everything, including files after the
first failure, so one run reports every error.

## How configuration works

GNU `configure` cannot run usefully on VMS, so it runs on the Linux host with VMS answers:

1. `tools/vms_configure.sh <node>` runs the upstream `configure` in cross mode, with
   `tools/vmscc` as the compiler. Every compile, link and preprocessor test is sent to
   `vms_ccserver.com` on the node and judged by VSI C. Results are memoised by content
   hash. It takes about 50–70 minutes and runs once per upstream release. The output is
   `overlay/vms/config/configure-<node>.cache` (committed).
2. `overlay/vms/config/vms-manual.site` holds hand-settled answers, each with a reason:
   run-time behaviour that cross mode cannot test, and CRTL quirks.
3. `overlay/vms/config/next-headers.site` (generated) maps gnulib's wrapper headers to
   CRTL text-library modules. VSI C has no `#include_next`, so gnulib's `lib/stdio.h`
   uses `#include STDIO`.
4. `tools/prepare.sh` replays those answers through the host `configure` offline. It
   generates `config.h`, the gnulib headers and `vms/sources.mms`, and records the result
   in `snapshot/` (committed). Review `git diff -- snapshot` whenever it changes.

## Moving to a new upstream release

1. Update `upstream.conf` (version, URL, SHA-256).
2. Run `tools/prepare.sh`. Patch rejects are the first to-do list.
3. Run `tools/vms_configure.sh ia64` (and `x86`) to refresh the answers. Compare the two
   cache files; so far they differ only in the CPU name.
4. Run `tools/prepare.sh` again, then review `git diff -- snapshot`.
5. Build and test on both nodes, then fix anything new with patches or overlay files.

## Layout of a prepared tree on VMS

```
[.GREP-3_12]            config.h, lib/, src/, vms/
[.GREP-3_12.VMS]        BUILD.COM, DESCRIP.MMS, SOURCES.MMS, TEST_SMOKE.COM, VMS_CRTL_INIT.C
[.GREP-3_12.OBJ_<arch>] objects (gnulib objects in [.LIB]), GREPUTILS.OLB, link map
[.GREP-3_12.BIN_<arch>] GREP.EXE
```

See `docs/PLAN.md` for the overall plan and `docs/vms-environment.md` for the
toolchain and CRTL findings that drive the configuration.
