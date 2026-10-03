$! BUILD.COM - build GNU grep for OpenVMS
$!
$! Usage:  @[.VMS]BUILD [target] [KEEP_GOING]
$!         target defaults to ALL; CLEAN also works.  KEEP_GOING carries on
$!         past failed compiles so one run reports every error.
$!
$! Runs from the top of the prepared source tree regardless of where it is
$! invoked from.  Output: [.BIN_<arch>]GREP.EXE
$!
$ status = 44  ! SS$_ABORT unless the build runs
$ on control_y then goto done
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$getsyi("ARCH_NAME")
$ if arch .eqs. "x86_64" then arch = "X86_64"
$ if arch .eqs. "IA64" .or. arch .eqs. "X86_64" then goto arch_ok
$ write sys$error "BUILD: unsupported architecture ''arch'"
$ goto done
$arch_ok:
$ if f$search("OBJ_''arch'.DIR") .eqs. "" then create/directory [.OBJ_'arch']
$ if f$search("[.OBJ_''arch']LIB.DIR") .eqs. "" then create/directory [.OBJ_'arch'.LIB]
$ if f$search("BIN_''arch'.DIR") .eqs. "" then create/directory [.BIN_'arch']
$! grep -P needs PCRE2 (github.com/issinoho/vms-pcre2): PCRE2$ROOT must be a
$! rooted logical for its install tree, e.g.
$!   $ DEFINE/TRANSLATION=CONCEALED PCRE2$ROOT dev:[dir.PCRE2-10_49.INSTALL_IA64.]
$ if f$trnlnm("PCRE2$ROOT") .eqs. "" .and. p1 .nes. "CLEAN"
$ then
$   write sys$error "BUILD: define PCRE2$ROOT for the PCRE2 install tree first (see README)"
$   goto done
$ endif
$ target = p1
$ if target .eqs. "" then target = "ALL"
$ write sys$output "BUILD: ''target' for ''arch' in ''f$environment("DEFAULT")'"
$ mmsq = ""
$ if p2 .eqs. "KEEP_GOING" then mmsq = "/IGNORE=ERROR"
$ mms/description=[.vms]descrip.mms/macro=("ARCH=''arch'")'mmsq' 'target'
$ status = $status
$ if status then write sys$output "BUILD: done"
$done:
$ set default 'saved_default'
$ exit status
