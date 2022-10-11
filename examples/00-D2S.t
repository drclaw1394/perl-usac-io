#run a udp server with socat
#socat UDP-LISTEN:5050 -
#
#stdin from this program will be send to socat
#stdin from socat will be sent to this program (after receiving first datagram)

use strict;
use warnings;



use feature ":all";

use Test::More;

use AnyEvent;


use uSAC::IO;
use Socket ":all";

my $cv=AE::cv;

my $port=5050;
my $host="localhost";

my $socket=uSAC::IO->socket(AF_INET, SOCK_DGRAM, 0);

uSAC::IO->connect(
	$socket,
	$host,
	$port,
	sub {
                my $reader=uSAC::IO::DReader->create(fh=>$_[0]);

                my $writer=uSAC::IO::SWriter->create(fh=>fileno STDOUT);
		$reader->pipe_to($writer);
                $reader->start;

		my $dwriter=uSAC::IO::DWriter->create(fh=>$_[0]);
		my $stdin=uSAC::IO::SReader->create(fh=>fileno STDIN);
		$stdin->pipe_to($dwriter);
		$stdin->start;
	},

	sub {
		say "ON ERROR";
		say $_[0];
		say $!;
		$cv->send;
	}
);
$cv->recv;
