use strict;
use warnings;
use feature ":all";
use AnyEvent;

use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in unpack_sockaddr_in inet_aton inet_ntoa>;

use uSAC::DIO;
my $cv=AE::cv;
my $dio;

connect_inet( "224.0.0.251", 5353,
	sub {
		say "Connect ok";
		#my $sockaddr=getpeername $_[0];
		my $sockaddr=getsockname $_[0];

		#bind $_[0], $sockaddr;

		$dio=uSAC::DIO->new(@_);
		my $timer;$timer=AE::timer 1, 1, sub {
			$dio->write(time,undef);
			$timer;

		};

		$dio->on_read=sub {
			say $_[0];
			#$_[0]="";
		};

		$dio->on_error=sub {
			say "Error ... $_[0]";

		};

		$dio->start;
	},

	sub {
		say "Connection Error";
		$cv->send;
		exit;
	}
);

$cv->recv;
