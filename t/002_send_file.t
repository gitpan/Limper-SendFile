use Test::More tests => 16;
use Limper::SendFile;
use Limper;
use POSIX qw(setsid);
use strict;
use warnings;

sub daemonize {
    chdir '/'                     or die "can't chdir to /: $!";
    open STDIN, '<', '/dev/null'  or die "can't read /dev/null: $!";
    open STDOUT, '>', '/dev/null' or die "can't write to /dev/null: $!";
    defined(my $pid = fork)       or die "can't fork: $!";
    return $pid if $pid;
    setsid != -1                  or die "Can't start a new session: $!";
    open STDERR, '>&', 'STDOUT'   or die "can't dup stdout: $!";
    0;
}

SKIP: {
    eval { require Net::HTTP::Client };

    skip "Net::HTTP::Client not installed", 8 if $@;

    my ($port, $sock);

    do {
        $port = int rand()*32767+32768;
        $sock = IO::Socket::INET->new(Listen => 5, ReuseAddr => 1, LocalAddr => 'localhost', LocalPort => $port, Proto => 'tcp')
                or warn "\n# cannot bind to port $port: $!";
    } while (!defined $sock);
    $sock->shutdown(2);
    $sock->close();

    my $pid = daemonize();
    if ($pid == 0) {

        public "$ENV{PWD}/t/foo";

        get qr{^/} => sub { send_file };

        limp(LocalPort => $port);
        die;
    } else {
        my $uri = "localhost:$port";
        sleep 1;

        my $res = Net::HTTP::Client->request(GET => "$uri/42");
        is $res->status_line, '404 Not Found', '404 status';
        is $res->content, 'This is the void', '404 body';

        $res = Net::HTTP::Client->request(GET => "$uri/../42");
        is $res->status_line, '403 Forbidden', '403 status';
        is $res->content, 'Forbidden', '403 body';

        $res = Net::HTTP::Client->request(GET => "$uri");
        is $res->status_line, '200 OK', 'Directory listing status';
        is $res->content, "<html><head><title>Directory listing of /</title></head><body>\n<a href=\"foo.txt\">foo.txt</a><br>\n</body></html>", 'Directory listing body';
        is $res->header('Content-Type'), 'text/html', 'Content-Type: text/html';

        $res = Net::HTTP::Client->request(GET => "$uri/foo.txt");
        is $res->status_line, '200 OK', '200 status';
        is $res->content, 'foo has some text', '200 body';
        is $res->header('Content-Type'), 'text/plain', 'Content-Type: text/plain';

	my $lm = $res->header('Last-Modified');
        $res = Net::HTTP::Client->request(GET => "$uri/foo.txt", 'If-Modified-Since' => $lm);
        is $res->status_line, '304 Not Modified', '304 status';
        is $res->content, '', '304 body';
        is $res->header('Content-Type'), 'text/plain', 'Content-Type: text/plain';

        $res = Net::HTTP::Client->request(GET => "$uri/foo.txt", 'If-Unmodified-Since' => $lm);
        is $res->status_line, '412 Precondition Failed', '412 status';
        is $res->content, '', '412 body';
        is $res->header('Content-Type'), 'text/plain', 'Content-Type: text/plain';

        kill -9, $pid;
    }
};
