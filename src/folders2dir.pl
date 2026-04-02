#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename qw(basename);
use File::Copy qw(move);
use File::Path qw(make_path);

my $VERSION = '0.1.0-2026.03.25';

my $dry_run = 0;
my $include_files = 0;
my $year_suffix = '';

sub print_usage {
    print <<'EOF';
Usage:
  folders2dir.pl [OPTIONS] PREFIX [PREFIX...]

Treat each PREFIX as a directory prefix and roll matching directories into a
directory named PREFIX.

Matching ignores a leading "[...]" tag and any spaces after it, and is
case-insensitive.

Immediate child files and directories from each matched source directory are
moved into the destination directory.

If a moved entry would clobber a name already present in the destination, it is
preserved under DEST/.#backup/SOURCE_DIR/ENTRY instead.

Options:
  --dry-run              Show what would be done, but do not move anything.
  --include-files        Also roll up matching top-level files from the current
                         directory.
  --year Y               Append year or year-range to created directory name,
                         e.g. "Foo (2004)" or "Foo (2001-2012)".
  --help                 Show this help message and exit.
  --version              Show version and exit.

Example:
  Suppose the current directory contains:
    Black One/cover.jpg
    Black One/notes.txt
    Black Two/cover.jpg
    Black Two/scan.png

  Running:
    folders2dir.pl Black

  Produces:
    Black/cover.jpg
    Black/notes.txt
    Black/scan.png
    Black/.#backup/Black Two/cover.jpg

  because the second cover.jpg would clobber the first one.
EOF
}

sub validate_year_arg {
    my ($year) = @_;
    return 1 if $year =~ /\A\d{4}\z/;
    return 1 if $year =~ /\A\d{4}-\d{4}\z/;
    return 0;
}

sub strip_leading_bracket_tag {
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
                return $rest;
            }
        }
        $i++;
    }

    return $text;
}

sub run_or_print {
    my ($message, $code) = @_;
    if ($dry_run) {
        print "$message\n";
        return;
    }
    $code->();
}

sub ensure_directory {
    my ($path) = @_;
    return if -d $path;
    run_or_print(qq{mkdir -p "$path"}, sub { make_path($path) });
}

sub collision_target {
    my ($destination, $source_dir_name, $entry_name) = @_;
    my $backup_root = "$destination/.#backup/$source_dir_name";
    my $candidate = "$backup_root/$entry_name";

    return $candidate if !-e $candidate;

    my $suffix = 1;
    while (-e "$candidate.$suffix") {
        $suffix++;
    }
    return "$candidate.$suffix";
}

sub move_entry {
    my ($source_path, $destination, $source_dir_name, $entry_name) = @_;
    my $direct_target = "$destination/$entry_name";
    my $target = $direct_target;

    if (-e $direct_target) {
      $target = collision_target($destination, $source_dir_name, $entry_name);
    }

    my $target_dir = $target;
    $target_dir =~ s{/[^/]+\z}{};
    ensure_directory($target_dir);

    run_or_print(qq{mv "$source_path" "$target"}, sub {
        move($source_path, $target)
          or die "Failed to move '$source_path' to '$target': $!";
    });
}

sub maybe_remove_source_dir {
    my ($path) = @_;
    opendir(my $dh, $path) or die "Failed to open '$path': $!";
    my @remaining = grep { $_ ne '.' && $_ ne '..' } readdir($dh);
    closedir($dh);

    return if @remaining;

    run_or_print(qq{rmdir "$path"}, sub {
        rmdir($path) or die "Failed to remove empty directory '$path': $!";
    });
}

sub process_prefix {
    my ($raw_prefix) = @_;
    my $prefix = strip_leading_bracket_tag($raw_prefix);
    my $destination = $prefix . $year_suffix;

    die "Error: prefix resolved to empty after stripping leading [..] tag: $raw_prefix\n"
      if $prefix eq '';

    opendir(my $cwd, '.') or die "Failed to open current directory: $!";
    my @matches;
    my $prefix_lc = lc($prefix);

    while (my $entry = readdir($cwd)) {
        next if $entry eq '.' || $entry eq '..';
        next if $entry eq $destination;

        if (!-d $entry) {
            next if !$include_files || !-f $entry;
        }

        my $normalized = strip_leading_bracket_tag($entry);
        next if index(lc($normalized), $prefix_lc) != 0;

        push @matches, $entry;
    }
    closedir($cwd);

    if (!@matches) {
        warn "Warning: no directories found starting with prefix (ignoring leading [..] tags): $prefix\n";
        return;
    }

    if (-e $destination && !-d $destination) {
        die "Error: '$destination' exists and is not a directory.\n";
    }

    ensure_directory($destination);

    for my $source_dir (sort @matches) {
        if (-f $source_dir) {
            move_entry($source_dir, $destination, '_top_level', basename($source_dir));
            next;
        }

        opendir(my $dirh, $source_dir) or die "Failed to open '$source_dir': $!";
        my @entries = grep { $_ ne '.' && $_ ne '..' } readdir($dirh);
        closedir($dirh);

        for my $entry (sort @entries) {
            my $source_path = "$source_dir/$entry";

            if (-f $source_path) {
                move_entry($source_path, $destination, basename($source_dir), $entry);
                next;
            }

            if (-d $source_path) {
                move_entry($source_path, $destination, basename($source_dir), $entry);
            }
        }

        maybe_remove_source_dir($source_dir);
    }
}

while (@ARGV) {
    my $arg = $ARGV[0];
    if ($arg eq '--dry-run') {
        $dry_run = 1;
        shift @ARGV;
        next;
    }
    if ($arg eq '--include-files') {
        $include_files = 1;
        shift @ARGV;
        next;
    }
    if ($arg eq '--year') {
        shift @ARGV;
        die "Error: --year requires YYYY or YYYY-YYYY.\n" if !@ARGV;
        die "Error: invalid --year value: '$ARGV[0]' (expected YYYY or YYYY-YYYY).\n"
          if !validate_year_arg($ARGV[0]);
        $year_suffix = " ($ARGV[0])";
        shift @ARGV;
        next;
    }
    if ($arg eq '--help') {
        print_usage();
        exit 0;
    }
    if ($arg eq '--version') {
        print "$VERSION\n";
        exit 0;
    }
    if ($arg eq '--') {
        shift @ARGV;
        last;
    }
    if ($arg =~ /\A--/) {
        die "Error: unknown option: $arg\nUse --help for usage.\n";
    }
    last;
}

die "Error: missing PREFIX.\nUse --help for usage.\n" if !@ARGV;

for my $prefix (@ARGV) {
    process_prefix($prefix);
}
