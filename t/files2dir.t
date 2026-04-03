use strict;
use warnings;

use Cwd qw(getcwd abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test2::V0;

my $repo_root = abs_path(getcwd());
my $script = "$repo_root/src/files2dir.pl";

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
    my $tmpdir = tempdir("files2dir-$name-XXXXXX", TMPDIR => 1, CLEANUP => 1);
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

subtest 'prefix mode strips a leading parenthetical before bracket tag' => sub {
    run_in_tempdir('prefix-normalization', sub {
        write_text('(1964) [TV] Black One.mkv', "one\n");
        write_text('(1964) [TV] Black Two.srt', "two\n");
        write_text('(1964) [TV] Blue One.txt', "blue\n");

        is(run_script('(1964) [TV] Black'), 0, 'command succeeds');

        ok(-d 'Black', 'destination uses normalized prefix');
        ok(-f 'Black/(1964) [TV] Black One.mkv', 'first matching file moved');
        ok(-f 'Black/(1964) [TV] Black Two.srt', 'second matching file moved');
        ok(-f '(1964) [TV] Blue One.txt', 'non-matching file left in place');
    });
};

subtest 'include-directories also uses the normalized prefix' => sub {
    run_in_tempdir('include-directories', sub {
        make_dir('(2004) [HD] Black Extras');
        write_text('(2004) [HD] Black Extras/cover.jpg', "cover\n");
        write_text('(2004) [HD] Black Main.mkv', "main\n");

        is(run_script('--include-directories', '(2004) [HD] Black'), 0, 'command succeeds');

        ok(-f 'Black/(2004) [HD] Black Main.mkv', 'matching file moved');
        ok(-d 'Black/(2004) [HD] Black Extras', 'matching directory moved');
        ok(-f 'Black/(2004) [HD] Black Extras/cover.jpg', 'moved directory keeps contents');
    });
};

subtest 'prefix matching is case-insensitive after stripping the leading tag' => sub {
    run_in_tempdir('case-insensitive-prefix', sub {
        write_text('[foo] De of Bar Primera.txt', "primera\n");
        write_text('[foo] De of bar CERO.txt', "cero\n");
        write_text('[foo] De of bar SEGUNDA.txt', "segunda\n");

        is(run_script('[foo] De of bar'), 0, 'command succeeds');

        ok(-d 'De of bar', 'destination directory uses normalized prefix text');
        ok(-f 'De of bar/[foo] De of Bar Primera.txt', 'mixed-case first file matched');
        ok(-f 'De of bar/[foo] De of bar CERO.txt', 'lowercase second file matched');
        ok(-f 'De of bar/[foo] De of bar SEGUNDA.txt', 'lowercase third file matched');
    });
};

subtest 'file mode still creates a directory from the file stem' => sub {
    run_in_tempdir('file-mode', sub {
        write_text('Episode 01.mkv', "episode\n");

        is(run_script('Episode 01.mkv'), 0, 'command succeeds');

        ok(-d './Episode 01', 'target directory created from file stem');
        ok(-f './Episode 01/Episode 01.mkv', 'file moved into target directory');
        is(slurp_text('./Episode 01/Episode 01.mkv'), "episode\n", 'file contents preserved');
    });
};

done_testing;
