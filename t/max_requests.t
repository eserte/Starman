use strict;
use warnings;

use Plack::Loader;
use Plack::Test;
use HTTP::Request;
use Plack::LWPish;
use Test::More;
use Test::TCP;

$Plack::Test::Impl = "Server";
$ENV{PLACK_SERVER} = 'Starman';

use Plack::Test::Server;
sub Plack::Test::Server::new {
    my($class, $app, %args) = @_;

    $args{server} ||= Test::TCP->new(
        code => sub {
            my $port = shift;
            my $server = Plack::Loader->auto(port => $port, host => ($args{host} || '127.0.0.1'));
            $server->run($app);
            exit;
        },
    );

    bless { %args }, $class;
}

my $app = do {
    my $requests = 0;
    sub {
	my $env = shift;
	return sub {
	    my $response = shift;
	    $requests++;
	    my $writer = $response->( [ 200, [ 'Content-Type', 'text/plain' ] ] );
	    $writer->write($requests);
	    $writer->close;
	}
    };
};

my $ua_without_keepalive = Plack::LWPish->new( no_proxy => [qw/127.0.0.1/], keep_alive => 0);
my $ua_with_keepalive    = Plack::LWPish->new( no_proxy => [qw/127.0.0.1/], keep_alive => 1);

test_psgi app => $app, ua => $ua_without_keepalive, client => sub {
    my $cb = shift;

    for my $no_req (1,1,2) { #(1, 2, 1) {
	my $req = HTTP::Request->new( GET => "http://localhost/" );
	my $res = $cb->($req);
	is $res->content, $no_req;
    }
}, server => Test::TCP->new(
    code => sub {
	my $port = shift;
	my $server = Plack::Loader->auto(port => $port, host => '127.0.0.1', max_requests => 2, workers => 1);
	$server->run($app);
	exit;
    },
);

test_psgi app => $app, ua => $ua_with_keepalive, client => sub {
    my $cb = shift;

    for my $no_req (1..3) {
	my $req = HTTP::Request->new( GET => "http://localhost/" );
	my $res = $cb->($req);
	is $res->content, $no_req;
    }
}, server => Test::TCP->new(
    code => sub {
	my $port = shift;
	my $server = Plack::Loader->auto(port => $port, host => '127.0.0.1', max_requests => 2, workers => 1);
	$server->run($app);
	exit;
    },
);

test_psgi app => $app, ua => $ua_with_keepalive, client => sub {
    my $cb = shift;

    for my $no_req (1..3) {
	my $req = HTTP::Request->new( GET => "http://localhost/" );
	my $res = $cb->($req);
	is $res->content, 1;
    }
}, server => Test::TCP->new(
    code => sub {
	my $port = shift;
	my $server = Plack::Loader->auto(port => $port, host => '127.0.0.1', max_requests => 1, max_keepalive_requests => 1, workers => 1);
	$server->run($app);
	exit;
    },
);

done_testing;
