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
$! Perl for the tests that need it (process-level names only).
$! Several versions may be installed; the last one found is the newest.
$ perl_setup = ""
$perl_loop:
$ f = f$search("SYS$COMMON:[PERL-5_*]PERL_SETUP.COM", 3)
$ if f .eqs. "" then goto perl_done
$ perl_setup = f
$ goto perl_loop
$perl_done:
$ if perl_setup .nes. "" then @'perl_setup'
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$! The tests run "grep" from ../src via PATH, and helpers from [.TESTS].
$ copy/nolog [.BIN_'arch']GREP.EXE [.SRC]GREP.EXE
$ purge/nolog [.SRC]GREP.EXE
$ mms/description=[.vms]descrip.mms/macro=("ARCH=''arch'") CHECK_PROGRAMS
$!
$! The tests ask for "en_US.UTF-8" and "fr_FR.UTF-8", which VMS does not ship
$! under those names.  Alias the newest generic UTF-8 locale to them in a
$! private directory searched first, for this process only.
$ locdir = f$environment("DEFAULT") - "]" + ".TESTS.VMS-LOCALE]"
$ if f$search("[.TESTS]VMS-LOCALE.DIR") .eqs. "" then create/directory 'locdir'
$ utf8 = ""
$ if f$search("SYS$I18N_LOCALE:UTF8-20.LOCALE") .nes. "" then utf8 = "UTF8-20"
$ if f$search("SYS$I18N_LOCALE:UTF8-30.LOCALE") .nes. "" then utf8 = "UTF8-30"
$ if f$search("SYS$I18N_LOCALE:UTF8-50.LOCALE") .nes. "" then utf8 = "UTF8-50"
$ if utf8 .eqs. "" then goto no_utf8
$ copy/nolog SYS$I18N_LOCALE:'utf8'.LOCALE 'locdir'EN_US_UTF-8.LOCALE
$ copy/nolog SYS$I18N_LOCALE:'utf8'.LOCALE 'locdir'FR_FR_UTF-8.LOCALE
$ purge/nolog 'locdir'
$ i18n = f$trnlnm("SYS$I18N_LOCALE")
$ define/process SYS$I18N_LOCALE 'locdir', 'i18n'
$ write sys$output "RUN_GNV_TESTS: en_US.UTF-8 and fr_FR.UTF-8 aliased to ''utf8'"
$no_utf8:
$ set process/parse_style=extended/case_lookup=blind
$ set default [.TESTS]
$ if p1 .nes. ""
$ then
$   bash ../vms/run_gnv_tests.sh 'p1' 'p2' 'p3' 'p4' 'p5' 'p6' 'p7' 'p8'
$   goto done
$ endif
$! Whole suite: a fresh bash per test (see run_gnv_tests.sh).
$ if f$search("vms-results.txt") .nes. "" then delete/nolog vms-results.txt;*
$ if f$search("[.vms-logs]*.*") .nes. "" then delete/nolog [.vms-logs]*.*;*
$ open/read tl [-.VMS]TESTS.LST
$test_loop:
$ read/end=test_done tl t
$ bash ../vms/run_gnv_tests.sh --append 't'
$ goto test_loop
$test_done:
$ close tl
$ bash ../vms/run_gnv_tests.sh --summary
$done:
$ set default 'saved_default'
$ exit 1
