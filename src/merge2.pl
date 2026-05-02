#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename qw(basename);
use File::Copy qw(move);

my $VERSION = '0.1.0-2026.05.02';

sub print_usage {
    print <<'EOF';
Usage:
  merge2.pl SOURCE... TARGET

Merge one or more SOURCE directories into TARGET using directory-only rules.

All SOURCE arguments and TARGET must be directories. Each SOURCE is merged as
TARGET/SOURCE_BASENAME, and SOURCE arguments are processed in the order given.

Rules:
  1. If TARGET/SOURCE_BASENAME does not exist, SOURCE is moved there.
  2. If TARGET/SOURCE_BASENAME already exists:
     - if SOURCE contains any immediate files, SOURCE is moved aside as
       TARGET/SOURCE_BASENAME.bak, adding more ".bak" suffixes until free.
     - if SOURCE contains only immediate directories, each child directory is
       checked:
         * if the child name does not exist in the target, it is moved there
         * if the child name exists as a directory, merge recurses one level deeper
         * if the child name exists and is not a directory, the source child is
           moved aside as CHILD.bak, adding more ".bak" suffixes until free
     - the first colliding source directory that has any immediate files is moved
       aside as NAME.bak rather than merged deeper.

Options:
  --help      Show this help message and exit.
  --version   Show version and exit.
EOF
}

sub read_entries {
    my ($directory) = @_;
    opendir(my $dh, $directory) or die "Failed to open '$directory': $!";
    my @entries = sort grep { $_ ne '.' && $_ ne '..' } readdir($dh);
    closedir($dh);
    return @entries;
}

sub contains_only_directories {
    my ($directory) = @_;
    for my $entry (read_entries($directory)) {
        return 0 if !-d "$directory/$entry";
    }
    return 1;
}

sub move_directory {
    my ($source, $destination) = @_;
    move($source, $destination)
      or die "Failed to move '$source' to '$destination': $!";
}

sub backup_path {
    my ($path) = @_;
    my $candidate = "$path.bak";
    while (-e $candidate) {
        $candidate .= '.bak';
    }
    return $candidate;
}

sub remove_if_empty {
    my ($directory) = @_;
    my @entries = read_entries($directory);
    return if @entries;
    rmdir($directory) or die "Failed to remove empty directory '$directory': $!";
}

sub merge_directory {
    my ($source, $target) = @_;

    if (!contains_only_directories($source)) {
        my $backup = backup_path($target);
        move_directory($source, $backup);
        return;
    }

    for my $entry (read_entries($source)) {
        my $source_child = "$source/$entry";
        my $target_child = "$target/$entry";

        die "Error: '$source_child' is not a directory.\n" if !-d $source_child;

        if (!-e $target_child) {
            move_directory($source_child, $target_child);
            next;
        }

        if (-d $target_child) {
            merge_directory($source_child, $target_child);
            next;
        }

        my $backup = backup_path($target_child);
        move_directory($source_child, $backup);
    }

    remove_if_empty($source);
}

sub merge_into_target {
    my ($source, $target_root) = @_;
    my $destination = "$target_root/" . basename($source);

    if (!-e $destination) {
        move_directory($source, $destination);
        return;
    }

    die "Error: '$destination' exists and is not a directory.\n" if !-d $destination;
    merge_directory($source, $destination);
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

die "Usage: merge2.pl SOURCE... TARGET\n" if @ARGV < 2;

my $target = pop @ARGV;
die "Error: TARGET '$target' is not a directory.\n" if !-d $target;

for my $source (@ARGV) {
    die "Error: SOURCE '$source' is not a directory.\n" if !-d $source;
}

for my $source (@ARGV) {
    merge_into_target($source, $target);
}
