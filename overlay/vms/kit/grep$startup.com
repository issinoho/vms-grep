$! GREP$STARTUP.COM - system startup for GNU grep on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! GREP$ROOT, pointing at the installed [GREP] directory.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:GREP$STARTUP.COM
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign GREP$ROOT instead (PCSI runs it so at removal).
$!
$! Users then define the grep, egrep and fgrep commands with
$!     $ @GREP$ROOT:[000000]GREP$SETUP.COM
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("GREP$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode GREP$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[GREP].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.GREP.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "GREP.]"
$ if root .eqs. dir + "GREP.]"
$ then
$   write sys$error "GREP$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed GREP$ROOT 'dev''root'
$ if f$search("GREP$ROOT:[BIN]GREP.EXE") .eqs. ""
$ then
$   write sys$error "GREP$STARTUP: GREP.EXE not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for GNU grep"
$ say ""
$ say "    At system startup: to define GREP$ROOT at every boot, add this line to"
$ say "    SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:GREP$STARTUP.COM"
$ say "    For each user: to define grep, egrep and fgrep, add this line to LOGIN.COM:"
$ say "    $ @GREP$ROOT:[000000]GREP$SETUP.COM"
$ say ""
$ say "    PRODUCT REMOVE GREP removes the product and deassigns GREP$ROOT."
$ say ""
$ exit 1
