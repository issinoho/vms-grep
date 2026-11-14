$! REGEX_TESTS_NOPERL.COM - grep's data-driven regex tests without Perl
$!
$! Started by REGEX_TESTS.COM from the top of the tree (OpenVMS Alpha has no VSI
$! Perl), with the foreign command VMSGREP defined and extended parsing set.
$! It does what regex_tests.pl does: reads tests/bre.tests, ere.tests and
$! spencer1.tests (lines "status@pattern@input"), writes the pattern and the
$! input to files, runs "grep -q [-E] -f pattern input" and compares the exit
$! status with the expected one.  Same cases, same messages, same totals.
$!
$! Usage:  @[.VMS]REGEX_TESTS_NOPERL      (from the top of the tree)
$! Exit status 1 if every case gave the expected status.
$!
$ set noon
$ total = 0
$ failed = 0
$ s = 0
$suite_loop:
$ s = s + 1
$ goto suite's'
$suite1:
$ file = "bre.tests"
$ opts = ""
$ goto suite_go
$suite2:
$ file = "ere.tests"
$ opts = "-E"
$ goto suite_go
$suite3:
$ file = "spencer1.tests"
$ opts = "-E"
$ goto suite_go
$suite4:
$ goto captured
$suite_go:
$ n = 0
$ bad = 0
$ open/read/error=nofile tf [.TESTS]'file'
$read_loop:
$ read/end=read_done tf line
$ if line .eqs. "" then goto read_loop
$ if f$extract(0, 1, line) .eqs. "#" then goto read_loop
$! Exactly three "@"-separated fields (4 fields: a known non-conformance).
$ if f$element(3, "@", line) .nes. "@" then goto read_loop
$ if f$element(2, "@", line) .eqs. "@" then goto read_loop
$ want = f$integer(f$element(0, "@", line))
$ pat = f$element(1, "@", line)
$ text = f$element(2, "@", line)
$ n = n + 1
$ gosub write_files
$ define/user sys$error nl:
$ if opts .eqs. ""
$ then
$   vmsgrep "-q" "-f" "rt-pat.tmp" "rt-in.tmp"
$ else
$   vmsgrep "-q" "''opts'" "-f" "rt-pat.tmp" "rt-in.tmp"
$ endif
$ st = $status
$ got = (st .and. %X7F8) / 8
$ if got .ne. want
$ then
$   bad = bad + 1
$   write sys$output "FAIL " + file + " #" + f$string(n) + ": grep " + opts + " -e '" + pat + "' on '" + text + "': exit " + f$string(got) + ", want " + f$string(want)
$ endif
$ goto read_loop
$read_done:
$ close tf
$ verdict = "PASS"
$ if bad .gt. 0 then verdict = "FAIL"
$ write sys$output "''verdict' ''file': ''n' cases, ''bad' failed"
$ total = total + n
$ failed = failed + bad
$ goto suite_loop
$nofile:
$ write sys$output "FAIL ''file': cannot open [.TESTS]''file'"
$ failed = failed + 1
$ goto suite_loop
$!
$! Output captured by another program goes through a mailbox, which fstat
$! cannot tell from /dev/null (patch 0010): grep must still print its lines.
$captured:
$ pat = "x"
$ text = "one"
$ gosub write_files
$ open/write f rt-in.tmp
$ write f "one"
$ write f "two"
$ write f "three"
$ close f
$ pipe vmsgrep "t" rt-in.tmp | copy sys$pipe rt-out.tmp
$ got = ""
$ open/read/error=cap_done f rt-out.tmp
$cap_loop:
$ read/end=cap_end f line
$ got = got + " " + line
$ goto cap_loop
$cap_end:
$ close f
$cap_done:
$ got = f$edit(got, "TRIM")
$ ok = (got .eqs. "two three")
$ verdict = "PASS"
$ if .not. ok then verdict = "FAIL"
$ write sys$output verdict + " captured output: got '" + got + "'"
$ total = total + 1
$ if .not. ok then failed = failed + 1
$ if f$search("rt-pat.tmp") .nes. "" then delete/nolog rt-pat.tmp;*
$ if f$search("rt-in.tmp") .nes. "" then delete/nolog rt-in.tmp;*
$ if f$search("rt-out.tmp") .nes. "" then delete/nolog rt-out.tmp;*
$ write sys$output "REGEX: ''total' cases, ''failed' failed"
$ if failed .eq. 0 then exit 1
$ exit 44
$!
$write_files:
$ if f$search("rt-pat.tmp") .nes. "" then delete/nolog rt-pat.tmp;*
$ if f$search("rt-in.tmp") .nes. "" then delete/nolog rt-in.tmp;*
$ open/write wf rt-pat.tmp
$ write wf pat
$ close wf
$ open/write wf rt-in.tmp
$ write wf text
$ close wf
$ return
