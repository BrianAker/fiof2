use strict;
use warnings;

use Cwd qw(getcwd abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test2::V0;

my $repo_root = abs_path(getcwd());
my $script = "$repo_root/src/folders2dir.pl";

sub write_text {
    my ($path, $content) = @_;
    my ($dir) = $path =~ m{\A(.+)/[^/]+\z};
    make_path($dir) if defined $dir && length $dir;

    open my $fh, '>', $path or die "open '$path': $!";
    print {$fh} $content;
    close $fh or die "close '$path': $!";
}

sub run_in_tempdir {
    my ($name, $code) = @_;

    my $original = getcwd();
    my $tmpdir = tempdir("folders2dir-$name-XXXXXX", TMPDIR => 1, CLEANUP => 1);
    chdir $tmpdir or die "chdir '$tmpdir': $!";

    my $ok = eval { $code->($tmpdir); 1 };
    my $err = $@;

    chdir $original or die "chdir '$original': $!";
    die $err if !$ok;
}

sub slurp_text {
    my ($path) = @_;
    open my $fh, '<', $path or die "open '$path': $!";
    local $/;
    my $content = <$fh>;
    close $fh or die "close '$path': $!";
    return $content;
}

sub run_script {
    my (@args) = @_;
    my $status = system('perl', $script, @args);
    return $status >> 8;
}

subtest 'rolls matching folders into destination and backs up collisions' => sub {
    run_in_tempdir('collision', sub {
        write_text('Black One/cover.jpg', "cover-from-one\n");
        write_text('Black One/notes.txt', "notes\n");
        write_text('Black Two/cover.jpg', "cover-from-two\n");
        write_text('Black Two/scan.png', "scan\n");

        is(run_script('Black'), 0, 'command succeeds');

        ok(-f 'Black/cover.jpg', 'first cover moved into destination');
        is(slurp_text('Black/cover.jpg'), "cover-from-one\n", 'original destination file preserved');
        ok(-f 'Black/notes.txt', 'notes moved');
        ok(-f 'Black/scan.png', 'scan moved');
        ok(-f 'Black/.#backup/Black Two/cover.jpg', 'colliding file moved into backup area');
        is(slurp_text('Black/.#backup/Black Two/cover.jpg'), "cover-from-two\n", 'backup keeps colliding content');
        ok(!-e 'Black One', 'empty source directory removed');
        ok(!-e 'Black Two', 'empty source directory removed');
    });
};

subtest 'backs up only the conflicting file when merging four directories' => sub {
    run_in_tempdir('partial-conflict-four-way', sub {
        write_text('Archive One/cover.jpg', "cover-one\n");
        write_text('Archive One/liner.txt', "liner-one\n");
        write_text('Archive Two/cover.jpg', "cover-two\n");
        write_text('Archive Two/lyrics.txt', "lyrics-two\n");
        write_text('Archive Three/cover.jpg', "cover-three\n");
        write_text('Archive Three/credits.txt', "credits-three\n");
        write_text('Archive Four/cover.jpg', "cover-four\n");
        write_text('Archive Four/poster.txt', "poster-four\n");

        is(run_script('Archive'), 0, 'command succeeds');

        ok(-f 'Archive/cover.jpg', 'one cover stays in the main destination');
        is(slurp_text('Archive/cover.jpg'), "cover-four\n", 'main destination keeps the first cover encountered in sort order');
        ok(-f 'Archive/liner.txt', 'non-conflicting file from Archive One moved into destination');
        ok(-f 'Archive/lyrics.txt', 'non-conflicting file from Archive Two moved into destination');
        ok(-f 'Archive/credits.txt', 'non-conflicting file from Archive Three moved into destination');
        ok(-f 'Archive/poster.txt', 'non-conflicting file from Archive Four moved into destination');
        ok(-f 'Archive/.#backup/Archive One/cover.jpg', 'Archive One conflicting cover moved to backup');
        is(slurp_text('Archive/.#backup/Archive One/cover.jpg'), "cover-one\n", 'Archive One backup keeps original content');
        ok(-f 'Archive/.#backup/Archive Two/cover.jpg', 'Archive Two conflicting cover moved to backup');
        is(slurp_text('Archive/.#backup/Archive Two/cover.jpg'), "cover-two\n", 'Archive Two backup keeps original content');
        ok(-f 'Archive/.#backup/Archive Three/cover.jpg', 'third conflicting cover moved to backup');
        is(slurp_text('Archive/.#backup/Archive Three/cover.jpg'), "cover-three\n", 'third backup keeps original content');
        ok(!-e 'Archive/.#backup/Archive Four/cover.jpg', 'sort-first directory keeps its cover in the main destination');
        ok(!-e 'Archive One', 'first source directory removed');
        ok(!-e 'Archive Two', 'second source directory removed');
        ok(!-e 'Archive Three', 'third source directory removed');
        ok(!-e 'Archive Four', 'fourth source directory removed');
    });
};

subtest 'default behavior moves child directories too' => sub {
    run_in_tempdir('default-directories', sub {
        write_text('Series One/episode1.mkv', "ep1\n");
        write_text('Series One/extras/interview.txt', "bonus\n");
        write_text('Series Two/episode2.mkv', "ep2\n");

        is(run_script('Series'), 0, 'command succeeds');

        ok(-f 'Series/episode1.mkv', 'file moved from first source directory');
        ok(-f 'Series/episode2.mkv', 'file moved from second source directory');
        ok(-d 'Series/extras', 'child directory moved by default');
        ok(-f 'Series/extras/interview.txt', 'child directory contents preserved');
        ok(!-e 'Series One', 'source directory removed after moving contents');
        ok(!-e 'Series Two', 'second source directory removed after moving contents');
    });
};

subtest 'rolls up both files and child directories from matching source folders' => sub {
    run_in_tempdir('mixed-entries', sub {
        write_text('Concert.txt', "top-level-file\n");
        write_text('Concert One/track01.flac', "track-one\n");
        write_text('Concert One/art/cover.jpg', "cover-one\n");
        write_text('Concert Two/track02.flac', "track-two\n");
        write_text('Concert Two/photos/live.jpg', "live-two\n");

        is(run_script('Concert'), 0, 'command succeeds');

        ok(-f 'Concert/track01.flac', 'file from first source folder moved');
        ok(-f 'Concert/track02.flac', 'file from second source folder moved');
        ok(-d 'Concert/art', 'child directory from first source folder moved');
        ok(-f 'Concert/art/cover.jpg', 'first moved child directory keeps contents');
        ok(-d 'Concert/photos', 'child directory from second source folder moved');
        ok(-f 'Concert/photos/live.jpg', 'second moved child directory keeps contents');
        ok(-f 'Concert.txt', 'top-level matching file is left in place');
        is(slurp_text('Concert.txt'), "top-level-file\n", 'top-level matching file is unchanged');
        ok(!-e 'Concert One', 'first source folder removed after roll-up');
        ok(!-e 'Concert Two', 'second source folder removed after roll-up');
    });
};

subtest 'include-files rolls up matching top-level files too' => sub {
    run_in_tempdir('mixed-entries-include-files', sub {
        write_text('Concert.txt', "top-level-file\n");
        write_text('Concert One/track01.flac', "track-one\n");
        write_text('Concert One/art/cover.jpg', "cover-one\n");
        write_text('Concert Two/track02.flac', "track-two\n");
        write_text('Concert Two/photos/live.jpg', "live-two\n");

        is(run_script('--include-files', 'Concert'), 0, 'command succeeds');

        ok(-f 'Concert/Concert.txt', 'top-level matching file moved into destination');
        is(slurp_text('Concert/Concert.txt'), "top-level-file\n", 'moved top-level file keeps contents');
        ok(-f 'Concert/track01.flac', 'file from first source folder moved');
        ok(-f 'Concert/track02.flac', 'file from second source folder moved');
        ok(-d 'Concert/art', 'child directory from first source folder moved');
        ok(-f 'Concert/art/cover.jpg', 'first moved child directory keeps contents');
        ok(-d 'Concert/photos', 'child directory from second source folder moved');
        ok(-f 'Concert/photos/live.jpg', 'second moved child directory keeps contents');
        ok(!-e 'Concert.txt', 'top-level matching file removed from current directory');
        ok(!-e 'Concert One', 'first source folder removed after roll-up');
        ok(!-e 'Concert Two', 'second source folder removed after roll-up');
    });
};

subtest 'year suffix and bracket tag normalization work together' => sub {
    run_in_tempdir('year-tag', sub {
        write_text('[HD] Black One/poster.jpg', "poster\n");
        write_text('[HD] Black Two/booklet.txt', "booklet\n");

        is(run_script('--year', '2004', '[HD] Black'), 0, 'command succeeds');

        ok(-d 'Black (2004)', 'destination uses stripped prefix plus year suffix');
        ok(-f 'Black (2004)/poster.jpg', 'poster moved');
        ok(-f 'Black (2004)/booklet.txt', 'booklet moved');
    });
};

done_testing;
