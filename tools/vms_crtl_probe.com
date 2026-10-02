$! VMS_CRTL_PROBE.COM - compile/link each probe C file and report results.
$! Usage: @VMS_CRTL_PROBE <dir-with-probe-files> [extra-cc-qualifiers]
$ set noon
$ say = "write sys$output"
$ dir = p1
$ proc = f$environment("PROCEDURE")
$ set default 'f$parse(proc,,,"DEVICE")''f$parse(proc,,,"DIRECTORY")'
$ ccq = "/NAMES=(AS_IS,SHORTENED)/FLOAT=IEEE/DEFINE=(_LARGEFILE,_USE_STD_STAT)/NOLIST/OBJECT=PROBE_TMP.OBJ" + p2
$ say "CCQUAL ", ccq
$ define/user sys$output nl:
$ define/user sys$error nl:
$ cc/standard=c99 'dir'l_c99.c/object=probe_tmp.obj
$ say "STD c99 ", $severity
$ define/user sys$output nl:
$ define/user sys$error nl:
$ cc/standard=latest 'dir'l_c99.c/object=probe_tmp.obj
$ say "STD latest ", $severity
$ define/user sys$output nl:
$ define/user sys$error nl:
$ cc/standard=c11 'dir'l_c99.c/object=probe_tmp.obj
$ say "STD c11 ", $severity
$loop:
$ f = f$search("''dir'*.c", 1)
$ if f .eqs. "" then goto done
$ n = f$parse(f,,,"NAME")
$ define/user sys$output probe_cc.lis
$ define/user sys$error probe_cc.lis
$ cc 'ccq' 'f'
$ csev = $severity
$ lsev = "-"
$ if csev .ne. 2 .and. csev .ne. 4
$ then
$   define/user sys$output probe_ln.lis
$   define/user sys$error probe_ln.lis
$   link/exe=probe_tmp.exe probe_tmp.obj
$   lsev = $severity
$ endif
$ msg = ""
$ open/read/error=nomsg in probe_cc.lis
$msgloop:
$ read/end=msgend in line
$ if f$extract(0,1,line) .eqs. "%" then msg = msg + " " + f$element(0,",",line)
$ goto msgloop
$msgend:
$ close in
$nomsg:
$ say "RESULT ", n, " cc=", csev, " link=", lsev, msg
$ if f$extract(0,2,n) .eqs. "R_" .and. lsev .eqs. "1" then run probe_tmp.exe
$ if f$search("probe_cc.lis") .nes. "" then delete/nolog probe_cc.lis;*
$ if f$search("probe_ln.lis") .nes. "" then delete/nolog probe_ln.lis;*
$ goto loop
$done:
$ if f$search("probe_tmp.*") .nes. "" then delete/nolog probe_tmp.*;*
$ say "=== DONE"
