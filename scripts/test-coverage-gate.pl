#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);

my $gate = abs_path('scripts/coverage-gate.pl')
    or die "coverage gate not found\n";

sub write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "cannot create $path: $!\n";
    print {$fh} $content;
    close $fh or die "cannot close $path: $!\n";
}

sub report_html {
    my ($source, $rows) = @_;
    return "<table><tr class='subheading'><td colspan='7'>$source/</td></tr>\n"
        . $rows . "</table>\n";
}

sub run_gate {
    my (%arguments) = @_;
    my ($diagnostic_fh, $diagnostic_path) = tempfile();
    close $diagnostic_fh or die "cannot close diagnostic file: $!\n";
    my @command = ($^X, $gate,
                   '--report-dir', $arguments{report},
                   '--source-dir', $arguments{source},
                   '--threshold', $arguments{threshold} // '100');
    push @command, '--output', $arguments{output} if defined $arguments{output};
    open my $saved_stdout, '>&', \*STDOUT
        or die "cannot preserve stdout: $!\n";
    open my $saved_stderr, '>&', \*STDERR
        or die "cannot preserve stderr: $!\n";
    open STDOUT, '>', $diagnostic_path
        or die "cannot redirect stdout: $!\n";
    open STDERR, '>&', \*STDOUT
        or die "cannot redirect stderr: $!\n";
    my $status = system(@command);
    open STDOUT, '>&', $saved_stdout
        or die "cannot restore stdout: $!\n";
    open STDERR, '>&', $saved_stderr
        or die "cannot restore stderr: $!\n";
    open my $result_fh, '<', $diagnostic_path
        or die "cannot read gate diagnostic: $!\n";
    local $/;
    my $diagnostic = <$result_fh>;
    close $result_fh or die "cannot close gate diagnostic: $!\n";
    return ($status, $diagnostic);
}

sub file_row {
    my ($file, $expressions_covered, $expressions_total,
        $branches_covered, $branches_total) = @_;
    return "<tr class='even'><td class='text-cell'><a href='$file.html'>$file.lisp</a></td>"
        . "<td>$expressions_covered</td><td>$expressions_total</td><td>-</td>"
        . "<td>$branches_covered</td><td>$branches_total</td><td>-</td></tr>\n";
}

my @cases = (
    {
        name => 'complete coverage',
        row => file_row('b', 3, 3, 2, 2),
        passes => 1,
    },
    {
        name => 'uncovered expression',
        row => file_row('b', 2, 3, 2, 2),
        diagnostic => qr/below required/,
    },
    {
        name => 'uncovered branch',
        row => file_row('b', 3, 3, 1, 2),
        diagnostic => qr/below required/,
    },
    {
        name => 'malformed row',
        row => "<tr class='even'><td><a href='b.html'>b.lisp</a></td><td>1</td></tr>\n",
        diagnostic => qr/malformed SB-COVER file row/,
    },
    {
        name => 'non-numeric count',
        row => file_row('b', 'unknown', 3, 0, 0),
        diagnostic => qr/non-numeric SB-COVER count/,
    },
    {
        name => 'zero measurable expressions',
        first_row => file_row('a', 0, 0, 0, 0),
        row => file_row('b', 0, 0, 0, 0),
        diagnostic => qr/zero measurable product expressions/,
    },
    {
        name => 'source missing from report',
        row => '',
        diagnostic => qr/product sources missing from SB-COVER report/,
    },
    {
        name => 'missing report',
        no_report => 1,
        diagnostic => qr/coverage report is missing or unreadable/,
    },
    {
        name => 'invalid threshold',
        row => file_row('b', 3, 3, 0, 0),
        threshold => '0',
        diagnostic => qr/coverage threshold must be in/,
    },
    {
        name => 'unwritable output',
        row => file_row('b', 3, 3, 0, 0),
        bad_output => 1,
        diagnostic => qr/cannot create coverage summary/,
    },
);

for my $case (@cases) {
    my $root = tempdir(CLEANUP => 1);
    my $source = File::Spec->catdir($root, 'src');
    my $report = File::Spec->catdir($root, 'report');
    make_path($source, $report);
    write_file(File::Spec->catfile($source, 'a.lisp'), "(defun a () t)\n");
    write_file(File::Spec->catfile($source, 'b.lisp'), "(defun b () t)\n");
    unless ($case->{no_report}) {
        my $first_row = $case->{first_row}
            // file_row('a', 2, 2, 1, 1);
        write_file(File::Spec->catfile($report, 'cover-index.html'),
                   report_html($source, $first_row . $case->{row}));
    }
    my $output = $case->{bad_output}
        ? File::Spec->catfile($root, 'missing', 'summary.json')
        : undef;
    my ($status, $diagnostic) = run_gate(
        report => $report,
        source => $source,
        threshold => $case->{threshold},
        output => $output,
    );
    if ($case->{passes}) {
        $status == 0
            or die "$case->{name} should pass:\n$diagnostic";
    } else {
        $status != 0
            or die "$case->{name} should fail\n";
        $diagnostic =~ $case->{diagnostic}
            or die "$case->{name} emitted an unexpected diagnostic:\n$diagnostic";
    }
}

print "coverage gate tests passed\n";
