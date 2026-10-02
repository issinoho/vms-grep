$! TEST_SMOKE.COM - quick functional check of a built or installed GREP.EXE
$!
$! Usage:  @[.VMS]TEST_SMOKE [grep-image]
$!         The default image is [.BIN_<arch>]GREP.EXE in this tree.
$! Exits with SS$_NORMAL if every test passes, otherwise reports failures.
$!
$ set noon
$ on control_y then goto finish
$ saved_default = f$environment("DEFAULT")
$ saved_parse = f$getjpi("", "PARSE_STYLE_PERM")
$ set process/parse_style=extended
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ image = p1
$ if image .eqs. "" then image = f$parse("[.BIN_''arch']GREP.EXE")
$ if f$search(image) .eqs. ""
$ then
$   write sys$error "SMOKE: no image ''image'"
$   exit 44
$ endif
$ grep := $'image'
$ pass == 0
$ fail == 0
$ if f$search("SMOKE_TMP.DIR") .eqs. "" then create/directory [.SMOKE_TMP]
$ set default [.SMOKE_TMP]
$ if f$search("*.*;*") .nes. "" then delete/nolog *.*;*
$!
$! --- fixtures -------------------------------------------------------------
$ create fruit.txt
apple
Banana
cherry pie
apple tart
grape
$ create/directory [.tree]
$ create [.tree]one.txt
needle in one
$ create [.tree]two.txt
no match here
$!
$! --- tests: name, expected exit code, expected output (| = newline), args --
$ call t version   0 ""                        "--version"
$ call t plain     0 "apple|apple tart"         "apple fruit.txt"
$ call t nomatch   1 ""                         "zebra fruit.txt"
$ call t nofile    2 ""                         "apple no_such_file.txt"
$ call t icase     0 "Banana"                   "-i banana fruit.txt"
$ call t case      1 ""                         "banana fruit.txt"
$ call t invert    0 "Banana|cherry pie|grape"  "-v apple fruit.txt"
$ call t count     0 "2"                        "-c apple fruit.txt"
$ call t number    0 "1:apple|4:apple tart"     "-n apple fruit.txt"
$ call t extended  0 "cherry pie|grape"         "-E ""^(cherry|grape)"" fruit.txt"
$ call t fixed     0 "cherry pie"               "-F ""y p"" fruit.txt"
$ call t word      0 "cherry pie"               "-w pie fruit.txt"
$ call t line      0 "apple"                    "-x apple fruit.txt"
$ call t only      0 "app|app"                  "-o app fruit.txt"
$ call t files     0 "fruit.txt"                "-l grape fruit.txt"
$ call t recurse   0 "tree/one.txt:needle in one" "-r needle tree"
$!
$finish:
$ set default 'vmsdir'
$ set default [-]
$ set process/parse_style='saved_parse'
$ write sys$output "SMOKE: ''pass' passed, ''fail' failed (''image')"
$ set default 'saved_default'
$ if fail .eq. 0 .and. pass .gt. 0 then exit 1
$ exit 44
$!
$! --- T name expected-exit expected-output args -------------------------
$t: subroutine
$ set noon
$ if f$search("out.txt") .nes. "" then delete/nolog out.txt;*
$ define/user sys$output out.txt
$ define/user sys$error out.txt
$ grep 'p4'
$ st = $status
$! _POSIX_EXIT: the C exit code is in bits 3..10 of the VMS status.
$ code = (st .and. %X7F8) / 8
$ got = ""
$ if f$search("out.txt") .eqs. "" then goto compare
$ open/read f out.txt
$readloop:
$ read/end=readdone f line
$ if got .nes. "" then got = got + "|"
$ got = got + line
$ if f$length(got) .gt. 200 then goto readdone
$ goto readloop
$readdone:
$ close f
$compare:
$ ok = code .eq. f$integer(p2)
$ if p1 .nes. "version" .and. p2 .ne. 2 then ok = ok .and. (got .eqs. p3)
$ if p1 .eqs. "version" then ok = ok .and. (f$locate("grep (GNU grep)", got) .lt. f$length(got))
$ if ok
$ then
$   write sys$output "PASS ", p1
$   pass == pass + 1
$ else
$   write sys$output "FAIL ", p1, ": exit ", code, " (want ", p2, "), output [", got, "] (want [", p3, "])"
$   fail == fail + 1
$ endif
$ exit 1
$ endsubroutine
