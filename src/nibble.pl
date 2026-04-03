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

If a name begins with a leading "(...)" tag followed by a "[...]" tag, both
prefixes and any following spaces are ignored before grouping.

Groups must share at least two tokens before they are reported.

Output format:
  COUNT PREFIX

Options:
  --help      Show this help message and exit.
  --version   Show version and exit.
EOF
}

sub balanced_suffix {
    my ($text, $open, $close) = @_;
    return undef if !defined($text) || $text eq '' || substr($text, 0, 1) ne $open;

    my $depth = 1;
    my $i = 1;
    my $len = length($text);

    while ($i < $len) {
        my $ch = substr($text, $i, 1);
        if ($ch eq $open) {
            $depth++;
        } elsif ($ch eq $close) {
            $depth--;
            if ($depth == 0) {
                return substr($text, $i + 1);
            }
        }
        $i++;
    }

    return undef;
}

sub normalize_name {
    my ($text) = @_;
    my $original = $text;

    if (defined($text) && $text ne '' && substr($text, 0, 1) eq '(') {
        my $after_paren = balanced_suffix($text, '(', ')');
        if (defined $after_paren) {
            $after_paren =~ s/\A\s+//;
            if (substr($after_paren, 0, 1) eq '[') {
                $text = $after_paren;
            } else {
                return $original;
            }
        } else {
            return $original;
        }
    }

    return $text if !defined($text) || $text eq '' || substr($text, 0, 1) ne '[';

    my $after_bracket = balanced_suffix($text, '[', ']');
    die "Error: unbalanced leading bracket tag in '$text'.\n" if !defined $after_bracket;

    $after_bracket =~ s/\A\s+//;
    $after_bracket =~ s/\A +//;
    $after_bracket =~ s/ +\z//;
    return $after_bracket;
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
    my @reference_lc = map { lc($_) } @reference;
    my $common = scalar @reference;

    for my $item (@{$items}[1 .. $#{$items}]) {
        my @tokens = @{ $item->{tokens} };
        my @tokens_lc = map { lc($_) } @tokens;
        $common = @tokens if @tokens < $common;

        my $i = 0;
        while ($i < $common) {
            last if $reference_lc[$i] ne $tokens_lc[$i];
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
        my $next = lc($item->{tokens}[$shared]);
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
    print "$result->[1] $result->[0]\n";
}
