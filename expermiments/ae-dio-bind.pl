use strict;
use warnings;
use feature ":all";
use AnyEvent;

use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in unpack_sockaddr_in inet_aton inet_ntoa>;

use uSAC::DIO;
my $cv=AE::cv;
my $sio;

bind_inet( "localhost", 5051,
	sub {
		my $addr;
		say "bind ok";
		say @_;
		$sio=uSAC::DIO->new(@_);
		$sio->on_read=sub {
			
			say "Got data: $_[0]";
			say "from address: ", $_[1];
			$addr=$_[1];
			my($port, $ip)=unpack_sockaddr_in $_[1];
			say "Port: $port, ip: @{[inet_ntoa $ip]}";
		};

		$sio->on_error=sub {
			say "ERROR";
		};

		$sio->start;

		my $timer;$timer=AE::timer 1, 1, sub {
			if($addr){
				$sio->write(time,undef,$addr);
				$timer;
			}

		};
	},
	sub {
		say "Cnnection Error";
		$cv->send;
		exit;
	}
);
$cv->recv;
