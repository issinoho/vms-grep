$! GREP$SETUP.COM - define the grep, egrep and fgrep commands for a user
$!
$! Add to LOGIN.COM (or SYS$MANAGER:SYLOGIN.COM for everyone):
$!     $ @GREP$ROOT:[000000]GREP$SETUP.COM
$!
$! Upper-case options and patterns need SET PROCESS/PARSE_STYLE=EXTENDED,
$! or double quotes, because traditional DCL parsing changes their case.
$! egrep and fgrep pass their option quoted, so they work either way.
$!
$ if f$trnlnm("GREP$ROOT") .eqs. ""
$ then
$   write sys$error "GREP$SETUP: GREP$ROOT is not defined; run GREP$STARTUP.COM first"
$   exit 44
$ endif
$ grep  :== $GREP$ROOT:[BIN]GREP.EXE
$! Quoted values keep the inner quotes, so the symbol passes "-E" intact.
$ egrep :== "$GREP$ROOT:[BIN]GREP.EXE ""-E"""
$ fgrep :== "$GREP$ROOT:[BIN]GREP.EXE ""-F"""
$ exit 1
