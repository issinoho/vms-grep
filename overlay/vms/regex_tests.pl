# regex_tests.pl - run grep's data-driven regex tests natively on OpenVMS.
#
# Reads the upstream tables tests/bre.tests, tests/ere.tests and
# tests/spencer1.tests (lines "status@pattern@input") that bre.awk, ere.awk
# and spencer1.awk normally turn into shell scripts, and runs each case
# through the VMS image directly - no GNV needed, so this also covers IA64.
#
# Patterns and inputs go through files (grep -f), which avoids DCL quoting
# and the loss of empty arguments.  The grep image is the DCL foreign
# command VMSGREP, defined by REGEX_TESTS.COM.
#
# Usage (from the tests directory):  perl ../vms/regex_tests.pl
# Exit status: 0 if every case gives the expected status, 1 otherwise.

use strict;
use warnings;

my @suites = (
    [ 'bre.tests',      [] ],     # grep -e PATTERN
    [ 'ere.tests',      ['-E'] ], # grep -E -e PATTERN
    [ 'spencer1.tests', ['-E'] ],
);

sub write_file {
    my ($name, $text) = @_;
    1 while unlink $name;     # VMS: remove every version, not just the latest
    open(my $fh, '>', $name) or die "$name: $!";
    print $fh $text, "\n";
    close $fh;
}

# VMS Perl decodes the POSIX-encoded exit status (grep is linked with
# /MAIN=POSIX_EXIT), so $? >> 8 is grep's exit code as on Unix.
sub posix_status {
    return $? == -1 ? -1 : $? >> 8;
}

my ($total, $failed) = (0, 0);
for my $suite (@suites) {
    my ($file, $opts) = @$suite;
    open(my $in, '<', $file) or die "$file: $!";
    my ($n, $bad) = (0, 0);
    while (my $line = <$in>) {
        chomp $line;
        next if $line =~ /^#/ or $line eq '';
        my @f = split /@/, $line, -1;
        next unless @f == 3;      # 4 fields: known non-conformance, not checked
        my ($want, $pat, $text) = @f;
        $n++;
        write_file('rt-pat.tmp', $pat);
        write_file('rt-in.tmp', $text);
        system('vmsgrep', '-q', @$opts, '-f', 'rt-pat.tmp', 'rt-in.tmp');
        my $got = posix_status();
        if ($got != $want) {
            $bad++;
            printf "FAIL %s #%d: grep %s-e '%s' on '%s': exit %d, want %d\n",
                $file, $n, join('', map { "$_ " } @$opts), $pat, $text, $got, $want;
        }
    }
    close $in;
    printf "%s %s: %d cases, %d failed\n", $bad ? 'FAIL' : 'PASS', $file, $n, $bad;
    $total += $n;
    $failed += $bad;
}
1 while unlink 'rt-pat.tmp', 'rt-in.tmp';
printf "REGEX: %d cases, %d failed\n", $total, $failed;
exit($failed ? 1 : 0);
