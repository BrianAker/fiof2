#!/usr/bin/env perl

use strict;
use warnings;

my $VERSION = '0.1.0-2026.03.25';
my $MIN_SHARED_TOKENS = 2;

sub print_usage {
    print <<'EOF';
Usage:
  nibble.pl [DIRECTORY]

Scan the immediate file and directory names in DIRECTORY, or the current
directory when DIRECTORY is omitted.

Before grouping, a leading "[...]" tag and any spaces after it are removed from
each name. The script then prints the longest shared prefixes measured in whole
space-delimited tokens for groups of two or more names.

Groups must share at least two tokens before they are reported.

Output format:
  PREFIX<TAB>COUNT

Options:
  --help      Show this help message and exit.
  --version   Show version and exit.
EOF
}

sub normalize_name {
    my ($text) = @_;
    return $text if !defined($text) || $text eq '' || substr($text, 0, 1) ne '[';

    my $depth = 1;
    my $i = 1;
    my $len = length($text);

    while ($i < $len) {
        my $ch = substr($text, $i, 1);
        if ($ch eq '[') {
            $depth++;
        } elsif ($ch eq ']') {
            $depth--;
            if ($depth == 0) {
                my $rest = substr($text, $i + 1);
                $rest =~ s/\A\s+//;
                $rest =~ s/\A +//;
                $rest =~ s/ +\z//;
                return $rest;
            }
        }
        $i++;
    }

    die "Error: unbalanced leading bracket tag in '$text'.\n";
}

sub read_entries {
    my ($directory) = @_;

    opendir(my $dh, $directory) or die "Failed to open '$directory': $!\n";
    my @names = sort grep { $_ ne '.' && $_ ne '..' && substr($_, 0, 1) ne '.' } readdir($dh);
    closedir($dh);

    my @items;
    for my $name (@names) {
        my $normalized = normalize_name($name);
        $normalized =~ s/\A +//;
        $normalized =~ s/ +\z//;
        next if $normalized eq '';

        my @tokens = grep { length $_ } split / /, $normalized;
        next if !@tokens;

        push @items, {
            name => $normalized,
            tokens => \@tokens,
        };
    }

    return @items;
}

sub common_prefix_length {
    my ($items) = @_;
    return 0 if @{$items} < 2;

    my @reference = @{ $items->[0]{tokens} };
    my $common = scalar @reference;

    for my $item (@{$items}[1 .. $#{$items}]) {
        my @tokens = @{ $item->{tokens} };
        $common = @tokens if @tokens < $common;

        my $i = 0;
        while ($i < $common) {
            last if $reference[$i] ne $tokens[$i];
            $i++;
        }
        $common = $i;
    }

    return $common;
}

sub emit_groups {
    my ($items, $results) = @_;
    return if @{$items} < 2;

    my $shared = common_prefix_length($items);
    if ($shared >= $MIN_SHARED_TOKENS) {
        my $prefix = join ' ', @{ $items->[0]{tokens} }[0 .. $shared - 1];
        push @{$results}, [$prefix, scalar(@{$items})];
        return;
    }

    my %buckets;
    for my $item (@{$items}) {
        next if @{ $item->{tokens} } <= $shared;
        my $next = $item->{tokens}[$shared];
        push @{ $buckets{$next} }, $item;
    }

    for my $key (sort keys %buckets) {
        next if @{ $buckets{$key} } < 2;
        emit_groups($buckets{$key}, $results);
    }
}

while (@ARGV) {
    my $arg = $ARGV[0];
    if ($arg eq '--help') {
        print_usage();
        exit 0;
    }
    if ($arg eq '--version') {
        print "$VERSION\n";
        exit 0;
    }
    last;
}

die "Usage: nibble.pl [DIRECTORY]\n" if @ARGV > 1;

my $directory = @ARGV ? $ARGV[0] : '.';
die "Error: '$directory' is not a directory.\n" if !-d $directory;

my @items = read_entries($directory);
my @results;
emit_groups(\@items, \@results);

for my $result (@results) {
    print "$result->[0]\t$result->[1]\n";
}
