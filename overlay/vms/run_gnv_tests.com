$! RUN_GNV_TESTS.COM - run the upstream test suite under GNV bash
$!
$! Usage:  @[.VMS]RUN_GNV_TESTS [test-name ...]
$! Needs a built [.BIN_<arch>]GREP.EXE and GNV (see GNV_ENV.COM).
$! Results: [.TESTS]VMS-RESULTS.TXT and [.TESTS.VMS-LOGS]
$!
$ set noon
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ @'vmsdir'GNV_ENV.COM
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$! The tests run "grep" from ../src via PATH.
$ copy/nolog [.BIN_'arch']GREP.EXE [.SRC]GREP.EXE
$ purge/nolog [.SRC]GREP.EXE
$ set process/parse_style=extended/case_lookup=blind
$ set default [.TESTS]
$ bash ../vms/run_gnv_tests.sh 'p1' 'p2' 'p3' 'p4' 'p5' 'p6' 'p7' 'p8'
$ set default 'saved_default'
$ exit 1
