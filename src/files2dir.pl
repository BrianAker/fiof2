#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename qw(basename dirname);
use File::Copy qw(move);
use File::Path qw(make_path);

my $VERSION = '1.7.0-2026.04.02';

my $force = 0;
my $dry_run = 0;
my $include_directories = 0;
my $read_null_arguments = 0;
my $year_suffix = q{};

sub print_usage {
    print <<'EOF';
Usage:
  files2dir [OPTIONS] ARG [ARG...]

If ARG is not an existing file:
  Treat ARG as a prefix and move filesystem entries whose names start with ARG
  into a directory named ARG.

  If a filename begins with a leading "[...]" tag, that tag and any following
  spaces are ignored for matching. Matching is case-insensitive.

  If a filename begins with a leading "(...)" tag followed by a "[...]" tag,
  both prefixes and any following spaces are ignored for matching.

If ARG begins with a leading "[...]" tag, that tag and any following spaces
are ignored for the directory name.

If ARG begins with a leading "(...)" tag followed by a "[...]" tag, both
prefixes and any following spaces are ignored for the directory name.

If ARG is an existing file with an extension:
  For each such file X.ext, create a directory "X" (if needed) and move
  X.ext into that directory.

Options:
  -0, --null             Read additional ARG values from stdin as NUL-delimited
                         strings.
  --force                Overwrite existing files in the target directory.
                         (Does not overwrite existing directories; those are skipped.)
  --dry-run              Show what would be done, but do not move anything.
  --include-directories  In prefix mode, include matching directories in addition to files.
  --year Y               Append year or year-range to created directory name, e.g.
                         "Foo (2004)" or "Foo (2001-2012)". Not used for matching.
  --help                 Show this help message and exit.
  --version              Show version and exit.

Examples:
  files2dir --year 2004 Black
    Creates ./Black (2004)/ and moves matching files into it.

  files2dir --include-directories Black
    Also moves matching directories into ./Black/
EOF
}

sub validate_year_arg {
    my ($year) = @_;
    return 1 if $year =~ /\A\d{4}\z/;
    return 1 if $year =~ /\A\d{4}-\d{4}\z/;
    return 0;
}

sub balanced_suffix {
    my ($text, $open, $close) = @_;
    return undef if !defined($text) || $text eq q{} || substr($text, 0, 1) ne $open;

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

sub strip_leading_prefixes {
    my ($text) = @_;
    my $original = $text;

    if (defined($text) && $text ne q{} && substr($text, 0, 1) eq '(') {
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

    if (defined($text) && $text ne q{} && substr($text, 0, 1) eq '[') {
        my $after_bracket = balanced_suffix($text, '[', ']');
        return $original if !defined $after_bracket;

        $after_bracket =~ s/\A\s+//;
        return $after_bracket;
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

sub read_null_arguments {
    my $stdin = q{};
    binmode(STDIN);
    while (1) {
        my $chunk = q{};
        my $read = sysread(STDIN, $chunk, 8192);
        die "Failed to read stdin: $!" if !defined $read;
        last if $read == 0;
        $stdin .= $chunk;
    }

    return () if $stdin eq q{};

    my @items = split /\0/, $stdin, -1;
    pop @items if @items && $items[-1] eq q{};
    return grep { $_ ne q{} } @items;
}

sub ensure_directory {
    my ($path) = @_;
    return if -d $path;

    run_or_print(qq{mkdir "$path"}, sub {
        mkdir($path) or die "Failed to create directory '$path': $!";
    });
}

sub move_path {
    my ($source, $destination) = @_;

    run_or_print(qq{mv "$source" "$destination"}, sub {
        move($source, $destination) or die "Failed to move '$source' to '$destination': $!";
    });
}

sub overwrite_file {
    my ($path) = @_;
    return if !-e $path;

    unlink($path) or die "Failed to remove '$path' before overwrite: $!";
}

sub process_prefix {
    my ($raw_prefix) = @_;
    my $prefix = strip_leading_prefixes($raw_prefix);
    my $destination = $prefix . $year_suffix;

    die "Error: prefix resolved to empty after stripping leading tags: $raw_prefix\n"
        if $prefix eq q{};

    opendir(my $cwd, '.') or die "Failed to open current directory: $!";
    my @matches;
    my $prefix_lc = lc($prefix);

    while (my $entry = readdir($cwd)) {
        next if $entry eq '.' || $entry eq '..';

        if (-f $entry) {
            # included
        } elsif ($include_directories && -d $entry) {
            # included
        } else {
            next;
        }

        my $normalized = strip_leading_prefixes($entry);
        next if index(lc($normalized), $prefix_lc) != 0;

        push @matches, $entry;
    }
    closedir($cwd);

    if (!@matches) {
        if ($include_directories) {
            warn "Warning: no files or directories found starting with prefix (ignoring leading tags): $prefix\n";
        } else {
            warn "Warning: no files found starting with prefix (ignoring leading tags): $prefix\n";
        }
        return;
    }

    if (-e $destination && !-d $destination) {
        die "Error: '$destination' exists and is not a directory.\n";
    }

    ensure_directory($destination);

    for my $source (sort @matches) {
        my $source_base = basename($source);

        if ($source_base eq $destination) {
            warn "Notice: matched destination directory '$destination' itself, skipping.\n";
            next;
        }

        my $target = "$destination/$source_base";
        if (-e $target) {
            if (-d $source) {
                warn "Warning: target '$target' already exists; refusing to overwrite/merge directory '$source_base'. Skipping.\n";
                next;
            }

            if (!$force) {
                warn "Warning: '$target' exists, use --force to overwrite. Skipping '$source_base'.\n";
                next;
            }

            if (-d $target) {
                warn "Warning: target '$target' already exists as a directory. Skipping '$source_base'.\n";
                next;
            }

            run_or_print(qq{rm "$target"}, sub { overwrite_file($target) });
        }

        move_path($source, $target);
    }
}

sub process_file {
    my ($file) = @_;
    if (!-f $file) {
        warn "Warning: '$file' is not a file, skipping.\n";
        return;
    }

    my $dirpath = dirname($file);
    my $filename = basename($file);
    my $stem = $filename;
    $stem =~ s/\.[^.]+\z//;

    my $target_dir = "$dirpath/$stem$year_suffix";
    my $destination = "$target_dir/$filename";

    if (-e $target_dir && !-d $target_dir) {
        die "Error: '$target_dir' exists but is not a directory.\n";
    }

    ensure_directory($target_dir);

    if (-e $destination && !$force) {
        warn "Warning: '$destination' exists, skipping (use --force to overwrite).\n";
        return;
    }

    if (-e $destination && -d $destination) {
        die "Error: '$destination' exists as a directory.\n";
    }

    if (-e $destination && $force) {
        run_or_print(qq{rm "$destination"}, sub { overwrite_file($destination) });
    }

    move_path($file, $destination);
}

while (@ARGV) {
    my $arg = $ARGV[0];
    if ($arg eq '--force') {
        $force = 1;
        shift @ARGV;
        next;
    }
    if ($arg eq '-0' || $arg eq '--null') {
        $read_null_arguments = 1;
        shift @ARGV;
        next;
    }
    if ($arg eq '--dry-run') {
        $dry_run = 1;
        shift @ARGV;
        next;
    }
    if ($arg eq '--include-directories') {
        $include_directories = 1;
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

push @ARGV, read_null_arguments() if $read_null_arguments;

die "Error: missing ARG.\nUse --help for usage.\n" if !@ARGV;

for my $arg (@ARGV) {
    if (-f $arg) {
        process_file($arg);
    } else {
        process_prefix($arg);
    }
}
