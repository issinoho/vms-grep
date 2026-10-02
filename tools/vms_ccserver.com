$! VMS_CCSERVER.COM - compile server for the host-side configure run (tools/vmscc)
$!
$! P1 = directory to serve (requests arrive there by sftp)
$! P2 = C compiler qualifiers
$!
$! Protocol, per test program <id>:
$!   host puts  <id>.C   - the source
$!   host puts  <id>.REQ - one line: compile | link | preprocess
$!   server writes <id>.LOG (compiler/linker messages), <id>.I (preprocess),
$!   then <id>.RES last: one line "ok" or "fail".
$! The host deletes the request files after collecting the result.
$! Create CCSERVER.STOP in P1 to stop; it also stops after ~30 minutes idle.
$!
$ set noon
$ set default 'p1'
$ ccq = p2
$ if f$search("CCSERVER.STOP") .nes. "" then delete/nolog CCSERVER.STOP;*
$ write sys$output "ccserver: serving ", f$environment("DEFAULT"), " with ", ccq
$ idle = 0
$loop:
$ if f$search("CCSERVER.STOP") .nes. "" then goto quit
$ req = f$search("*.REQ", 7)
$ if req .eqs. ""
$ then
$   wait 0:0:0.25
$   idle = idle + 1
$   if idle .gt. 7200 then goto quit
$   goto loop
$ endif
$ idle = 0
$ id = f$parse(req,,,"NAME")
$ open/read/error=loop r 'req'
$ read/end=badreq r mode
$badreq:
$ close r
$ if f$search("''id'.LOG") .nes. "" then delete/nolog 'id'.LOG;*
$ define/user sys$output 'id'.LOG
$ define/user sys$error 'id'.LOG
$ if mode .eqs. "preprocess"
$ then
$   cc 'ccq' /nolist/noobject/preprocess_only='id'.I 'id'.C
$ else
$   cc 'ccq' /nolist/object='id'.OBJ 'id'.C
$ endif
$ sev = $severity
$ ok = (sev .ne. 2) .and. (sev .ne. 4)
$ if ok .and. mode .eqs. "link"
$ then
$   define/user sys$output 'id'.LLOG
$   define/user sys$error 'id'.LLOG
$   link/nomap/executable='id'.EXE 'id'.OBJ
$   ok = $severity .eq. 1
$   if f$search("''id'.LLOG") .nes. ""
$   then
$     append/new_version 'id'.LLOG 'id'.LOG
$     delete/nolog 'id'.LLOG;*
$   endif
$ endif
$ open/write o 'id'.TRS
$ if ok
$ then write o "ok"
$ else write o "fail"
$ endif
$ close o
$ rename 'id'.TRS 'id'.RES
$ delete/nolog 'req'
$ if f$search("''id'.OBJ") .nes. "" then delete/nolog 'id'.OBJ;*
$ if f$search("''id'.EXE") .nes. "" then delete/nolog 'id'.EXE;*
$ goto loop
$quit:
$ if f$search("CCSERVER.STOP") .nes. "" then delete/nolog CCSERVER.STOP;*
$ write sys$output "ccserver: stopping"
