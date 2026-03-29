use strict;
use warnings;

use Cwd qw(getcwd abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use Test2::V0;

my $repo_root = abs_path(getcwd());
my $script = "$repo_root/src/nibble.pl";

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

sub run_in_tempdir {
    my ($name, $code) = @_;

    my $original = getcwd();
    my $tmpdir = tempdir("nibble-$name-XXXXXX", TMPDIR => 1, CLEANUP => 1);
    chdir $tmpdir or die "chdir '$tmpdir': $!";

    my $ok = eval { $code->($tmpdir); 1 };
    my $err = $@;

    chdir $original or die "chdir '$original': $!";
    die $err if !$ok;
}

sub run_script {
    my (@args) = @_;
    my $stderr = gensym();
    my $pid = open3(undef, my $stdout, $stderr, 'perl', $script, @args);

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

subtest 'groups current directory entries by longest shared token prefix' => sub {
    run_in_tempdir('current-dir', sub {
        write_text('[HD] Black Show One.mkv', "one\n");
        write_text('Black Show Two.srt', "two\n");
        make_dir('Blue Note One');
        make_dir('Blue Note Two');
        write_text('Solo.txt', "solo\n");

        my ($status, $output, $error) = run_script();
        is($status, 0, 'command succeeds');
        is($error, '', 'stderr is empty');
        is([sort split /\n/, $output], ["Black Show\t2", "Blue Note\t2"], 'reports grouped prefixes and counts');
    });
};

subtest 'uses the first argument as the scan directory' => sub {
    run_in_tempdir('argument-dir', sub {
        make_dir('library');
        write_text('library/[TV] Alpha Series One.avi', "one\n");
        write_text('library/[TV] Alpha Series Two.avi', "two\n");
        write_text('library/Beta.dat', "beta\n");

        my ($status, $output, $error) = run_script('library');
        is($status, 0, 'command succeeds');
        is($error, '', 'stderr is empty');
        is($output, "Alpha Series\t2\n", 'scans the requested directory');
    });
};

subtest 'ignores hidden entries when grouping' => sub {
    run_in_tempdir('hidden', sub {
        write_text('.hidden-one', "x\n");
        write_text('.hidden-two', "y\n");
        write_text('Gamma Ray One.txt', "one\n");
        write_text('Gamma Ray Two.txt', "two\n");

        my ($status, $output, $error) = run_script();
        is($status, 0, 'command succeeds');
        is($error, '', 'stderr is empty');
        is($output, "Gamma Ray\t2\n", 'hidden entries are ignored');
    });
};

subtest 'prefers the shared word sequence and ignores one-word overlaps' => sub {
    run_in_tempdir('word-groups', sub {
        write_text('One Fish Two Fish', "a\n");
        write_text('One Fish Two Fish La', "b\n");
        write_text('One Firsh Two', "c\n");
        write_text('One Fish Two Fishes', "d\n");
        write_text('One Frog Red', "e\n");
        write_text('One Lizard Blue', "f\n");

        my ($status, $output, $error) = run_script();
        is($status, 0, 'command succeeds');
        is($error, '', 'stderr is empty');
        is($output, "One Fish Two\t3\n", 'reports the longest shared token sequence for the multi-name group');
    });
};

subtest 'throws an error for an unbalanced leading bracket tag' => sub {
    run_in_tempdir('unbalanced-tag', sub {
        write_text('[broken Name One', "a\n");
        write_text('Broken Name Two', "b\n");

        my ($status, $output, $error) = run_script();
        isnt($status, 0, 'command fails');
        is($output, '', 'stdout is empty on error');
        like($error, qr/unbalanced leading bracket tag/, 'stderr reports the malformed tag');
    });
};

done_testing;
