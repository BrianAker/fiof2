use strict;
use warnings;

use Cwd qw(getcwd abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test2::V0;

my $repo_root = abs_path(getcwd());
my $script = "$repo_root/src/merge2.pl";

sub write_text {
    my ($path, $content) = @_;
    my ($dir) = $path =~ m{\A(.+)/[^/]+\z};
    make_path($dir) if defined $dir && length $dir;

    open my $fh, '>', $path or die "open '$path': $!";
    print {$fh} $content;
    close $fh or die "close '$path': $!";
}

sub make_dir {
    my ($path) = @_;
    make_path($path);
}

sub slurp_text {
    my ($path) = @_;
    open my $fh, '<', $path or die "open '$path': $!";
    local $/;
    my $content = <$fh>;
    close $fh or die "close '$path': $!";
    return $content;
}

sub run_in_tempdir {
    my ($name, $code) = @_;

    my $original = getcwd();
    my $tmpdir = tempdir("merge2-$name-XXXXXX", TMPDIR => 1, CLEANUP => 1);
    chdir $tmpdir or die "chdir '$tmpdir': $!";

    my $ok = eval { $code->($tmpdir); 1 };
    my $err = $@;

    chdir $original or die "chdir '$original': $!";
    die $err if !$ok;
}

sub run_script {
    my (@args) = @_;
    my $status = system('perl', $script, @args);
    return $status >> 8;
}

subtest 'moves the source directory under the target when there is no collision' => sub {
    run_in_tempdir('simple-move', sub {
        make_dir('A');
        write_text('B/file.txt', "payload\n");

        is(run_script('B', 'A'), 0, 'command succeeds');
        ok(-d 'A/B', 'source directory moved under target');
        ok(-f 'A/B/file.txt', 'moved directory keeps contents');
        ok(!-e 'B', 'original source path removed');
    });
};

subtest 'processes multiple source directories into the final target directory' => sub {
    run_in_tempdir('multiple-sources', sub {
        make_dir('Target');
        write_text('Alpha/one.txt', "one\n");
        write_text('Beta/two.txt', "two\n");

        is(run_script('Alpha', 'Beta', 'Target'), 0, 'command succeeds');
        ok(-f 'Target/Alpha/one.txt', 'first source moved into target');
        ok(-f 'Target/Beta/two.txt', 'second source moved into target');
        ok(!-e 'Alpha', 'first source removed from original location');
        ok(!-e 'Beta', 'second source removed from original location');
    });
};

subtest 'multiple sources are processed in the order provided' => sub {
    run_in_tempdir('source-order', sub {
        make_dir('Target/B');
        write_text('Target/B/original.txt', "original\n");
        write_text('First/B/from-first.txt', "first\n");
        write_text('Second/B/from-second.txt', "second\n");

        is(run_script('First/B', 'Second/B', 'Target'), 0, 'command succeeds');
        ok(-d 'Target/B.bak', 'first colliding source claims the first backup name');
        ok(-f 'Target/B.bak/from-first.txt', 'first source is handled before the second');
        ok(-d 'Target/B.bak.bak', 'second colliding source gets the next backup name');
        ok(-f 'Target/B.bak.bak/from-second.txt', 'second source is handled after the first');
        ok(-f 'Target/B/original.txt', 'original target directory remains in place');
        ok(!-e 'First/B', 'first source path removed');
        ok(!-e 'Second/B', 'second source path removed');
    });
};

subtest 'recurses through directory-only collisions and backs up the first directory with files' => sub {
    run_in_tempdir('recursive-merge', sub {
        make_dir('A/B/Season 1/Disc A');
        write_text('A/B/Season 1/Disc A/existing.txt', "existing\n");

        write_text('B/Season 1/Disc A/new.txt', "new\n");
        write_text('B/Season 1/Disc B/bonus.txt', "bonus\n");
        write_text('B/Season 2/Disc C/fresh.txt', "fresh\n");

        is(run_script('B', 'A'), 0, 'command succeeds');

        ok(-f 'A/B/Season 1/Disc A/existing.txt', 'original target directory stays in place');
        ok(-d 'A/B/Season 1/Disc A.bak', 'colliding source directory with files is renamed aside');
        ok(-f 'A/B/Season 1/Disc A.bak/new.txt', 'backed up colliding directory keeps contents');
        ok(-f 'A/B/Season 1/Disc B/bonus.txt', 'non-colliding sibling moved into existing branch');
        ok(-f 'A/B/Season 2/Disc C/fresh.txt', 'new branch moved into target');
        ok(!-e 'B', 'source directory removed after recursive merge');
    });
};

subtest 'adds repeated .bak suffixes until a free name is found' => sub {
    run_in_tempdir('root-backup-suffix', sub {
        make_dir('A/B');
        make_dir('A/B.bak');
        write_text('A/B/kept.txt', "kept\n");
        write_text('A/B.bak/older.txt', "older\n");
        write_text('B/file.txt', "incoming\n");

        is(run_script('B', 'A'), 0, 'command succeeds');

        ok(-d 'A/B.bak.bak', 'source directory renamed with an additional .bak suffix');
        ok(-f 'A/B.bak.bak/file.txt', 'renamed backup directory keeps contents');
        ok(-f 'A/B/kept.txt', 'original target directory remains untouched');
        ok(-f 'A/B.bak/older.txt', 'existing backup directory remains untouched');
        ok(!-e 'B', 'source directory removed from original location');
    });
};

subtest 'backs up a deeper collision when the target child is not a directory' => sub {
    run_in_tempdir('child-file-collision', sub {
        make_dir('A/B/Season 1');
        write_text('A/B/Season 1/Disc A', "file-collision\n");
        write_text('B/Season 1/Disc A/new.txt', "new\n");

        is(run_script('B', 'A'), 0, 'command succeeds');

        ok(-f 'A/B/Season 1/Disc A', 'target file remains in place');
        ok(-d 'A/B/Season 1/Disc A.bak', 'source directory is renamed aside when child collides with a file');
        ok(-f 'A/B/Season 1/Disc A.bak/new.txt', 'renamed child directory keeps contents');
        ok(!-e 'B', 'source directory removed after merge');
    });
};

done_testing;
