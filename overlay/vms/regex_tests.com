$! REGEX_TESTS.COM - run grep's data-driven regex tests with VSI Perl
$!
$! Usage:  @[.VMS]REGEX_TESTS [grep-image]
$!         The default image is [.BIN_<arch>]GREP.EXE in this tree.
$! Needs VSI Perl (SYS$COMMON:[PERL-5_*]PERL_SETUP.COM); not GNV.
$!
$ set noon
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ image = p1
$ if image .eqs. "" then image = f$parse("[.BIN_''arch']GREP.EXE")
$ vmsgrep :== $'image'
$! Several Perl versions may be installed; the last one found is the newest.
$ perl_setup = ""
$perl_loop:
$ f = f$search("SYS$COMMON:[PERL-5_*]PERL_SETUP.COM", 4)
$ if f .eqs. "" then goto perl_done
$ perl_setup = f
$ goto perl_loop
$perl_done:
$ if perl_setup .eqs. ""
$ then
$   write sys$error "REGEX_TESTS: VSI Perl not found"
$   status = 44
$   goto finish
$ endif
$ @'perl_setup'
$ set default [.TESTS]
$! Without extended parsing DCL upper-cases the command line and the CRTL
$! lower-cases argv, so "-E" would reach grep as "-e".
$ saved_parse = f$getjpi("", "PARSE_STYLE_PERM")
$ set process/parse_style=extended
$ perl ../vms/regex_tests.pl
$ status = $status
$ set process/parse_style='saved_parse'
$finish:
$ set default 'saved_default'
$ delete/symbol/global vmsgrep
$ exit status
