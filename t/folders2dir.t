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
