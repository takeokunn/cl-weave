#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Find qw(find);
use File::Spec;
use Getopt::Long qw(GetOptions);

my ($report_dir, $source_dir, $output);
my $threshold = 100;
GetOptions(
    'report-dir=s' => \$report_dir,
    'source-dir=s' => \$source_dir,
    'threshold=f' => \$threshold,
    'output=s' => \$output,
) or die "usage: $0 --report-dir DIR --source-dir DIR [--threshold 100] [--output FILE]\n";

defined $report_dir && defined $source_dir
    or die "usage: $0 --report-dir DIR --source-dir DIR [--threshold 100] [--output FILE]\n";
$threshold > 0 && $threshold <= 100
    or die "coverage threshold must be in (0, 100]\n";

my $index = File::Spec->catfile($report_dir, 'cover-index.html');
open my $index_fh, '<', $index
    or die "coverage report is missing or unreadable: $index: $!\n";
local $/;
my $html = <$index_fh>;
close $index_fh or die "cannot close coverage report: $index: $!\n";

sub html_text {
    my ($text) = @_;
    $text =~ s/<[^>]+>//g;
    $text =~ s/&amp;/&/g;
    $text =~ s/&lt;/</g;
    $text =~ s/&gt;/>/g;
    $text =~ s/&#39;/'/g;
    $text =~ s/&quot;/"/g;
    return $text;
}

my $source_root = abs_path($source_dir)
    or die "product source directory is missing: $source_dir\n";
my %expected;
find(
    sub {
        return unless -f $_ && /[.]lisp\z/;
        my $path = abs_path($File::Find::name);
        $expected{$path} = 1;
    },
    $source_root,
);
%expected or die "product source directory contains no Lisp files: $source_root\n";

my ($directory, %measured);
while ($html =~ m{(<tr class='(?:subheading|odd|even)'>.*?</tr>)}sg) {
    my $row = $1;
    if ($row =~ /class='subheading'/) {
        $row =~ m{<td[^>]*>(.*?)</td>}s
            or die "malformed SB-COVER directory row\n";
        $directory = html_text($1);
        next;
    }
    next unless defined $directory && $row =~ m{<a [^>]*>(.*?)</a>}s;
    my $file = html_text($1);
    my @cells = map { html_text($_) } ($row =~ m{<td[^>]*>(.*?)</td>}sg);
    @cells == 7 or die "malformed SB-COVER file row for $file\n";
    my $path = abs_path(File::Spec->catfile($directory, $file));
    next unless defined $path && exists $expected{$path};
    for my $index (1, 2, 4, 5) {
        $cells[$index] =~ /\A\d+\z/
            or die "non-numeric SB-COVER count for $path\n";
    }
    $measured{$path} = {
        expression_covered => 0 + $cells[1],
        expression_total => 0 + $cells[2],
        branch_covered => 0 + $cells[4],
        branch_total => 0 + $cells[5],
    };
}

my @missing = sort grep { !exists $measured{$_} } keys %expected;
@missing and die "product sources missing from SB-COVER report:\n  "
    . join("\n  ", @missing) . "\n";

my ($expression_covered, $expression_total, $branch_covered, $branch_total) = (0, 0, 0, 0);
for my $counts (values %measured) {
    $expression_covered += $counts->{expression_covered};
    $expression_total += $counts->{expression_total};
    $branch_covered += $counts->{branch_covered};
    $branch_total += $counts->{branch_total};
}
$expression_total > 0
    or die "SB-COVER reported zero measurable product expressions\n";

my $covered = $expression_covered + $branch_covered;
my $total = $expression_total + $branch_total;
my $rate = 100 * $covered / $total;
my $summary = sprintf(
    '{"source_files":%d,"expressions":{"covered":%d,"total":%d},'
    . '"branches":{"covered":%d,"total":%d},"rate":%.6f,"threshold":%.6f}',
    scalar(keys %measured), $expression_covered, $expression_total,
    $branch_covered, $branch_total, $rate, $threshold,
);

if (defined $output) {
    open my $output_fh, '>', $output
        or die "cannot create coverage summary $output: $!\n";
    print {$output_fh} "$summary\n";
    close $output_fh or die "cannot close coverage summary $output: $!\n";
}
print "$summary\n";

$rate + 1e-9 >= $threshold
    or die sprintf("product coverage %.6f%% is below required %.6f%%\n", $rate, $threshold);

