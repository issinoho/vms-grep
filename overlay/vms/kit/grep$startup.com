$! GREP$STARTUP.COM - system startup for GNU grep on OpenVMS
$!
$! Defines the system logical name GREP$ROOT, pointing at the installed
$! [GREP] directory.  Run it at system startup by adding this line to
$! SYS$MANAGER:SYSTARTUP_VMS.COM (the path is where PCSI installed grep):
$!
$!     $ @<destination>:[GREP]GREP$STARTUP.COM
$!
$! With P1 = "REMOVE" it deassigns GREP$ROOT instead (used at kit removal).
$! Users then define the grep, egrep and fgrep commands with
$!     $ @GREP$ROOT:[000000]GREP$SETUP.COM
$!
$ set noon
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$parse(proc,,,"DIRECTORY","NO_CONCEAL")
$! A rooted logical needs the physical form: DKA0:[SYS0.SYSCOMMON.GREP.]
$ dir = dir - "][" - "]" + ".]"
$ dir = dir - ".000000"
$ if f$edit(p1, "UPCASE") .eqs. "REMOVE"
$ then
$   if f$trnlnm("GREP$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system GREP$ROOT
$   exit 1
$ endif
$ define/system/executive_mode/translation_attributes=concealed GREP$ROOT 'dev''dir'
$ exit 1
