use strict;
use warnings;

use Cwd qw(getcwd abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use Test2::V0;

my $repo_root = abs_path(getcwd());
my $script = "$repo_root/src/files2dir.pl";
my $nibble = "$repo_root/src/nibble.pl";
my $perl = $^X;

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

sub run_pipeline {
    my ($producer, $consumer) = @_;

    my $stderr = gensym();
    my $command = qq{$perl "$producer" --null | $perl "$consumer" --null};
    my $pid = open3(undef, my $stdout, $stderr, '/bin/sh', '-c', $command);

    my $out = do {
        local $/;
        <$stdout>;
    };
    my $err = do {
        local $/;
        <$stderr>;
    };

    waitpid($pid, 0);
    my $status = $? >> 8;
    return ($status, $out, $err);
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

subtest 'null mode can consume prefixes from nibble' => sub {
    run_in_tempdir('null-pipeline', sub {
        write_text('Black Show One.mkv', "one\n");
        write_text('Black Show Two.srt', "two\n");
        write_text('Blue Note One.txt', "three\n");
        write_text('Blue Note Two.jpg', "four\n");

        my ($status, $output, $error) = run_pipeline($nibble, $script);
        is($status, 0, 'pipeline succeeds');
        is($output, '', 'stdout is empty');
        is($error, '', 'stderr is empty');
        ok(-f 'Black Show/Black Show One.mkv', 'first nibble prefix fed into files2dir');
        ok(-f 'Black Show/Black Show Two.srt', 'second matching file moved');
        ok(-f 'Blue Note/Blue Note One.txt', 'third file moved under second prefix');
        ok(-f 'Blue Note/Blue Note Two.jpg', 'fourth file moved under second prefix');
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
