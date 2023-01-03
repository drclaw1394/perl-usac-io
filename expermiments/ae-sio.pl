use strict;
use warnings;
use feature ":all";
use AnyEvent;

use uSAC::SIO;
my $cv=AE::cv;
my $sio;

connect_inet("localhost", 5050,
	sub {
		say "Connection ok";
		$sio=uSAC::SIO->new(@_);
		$sio->on_read=sub {
			say "Got data: $_[1]";
			$_[1]="";
		};
		$sio->start;
	},
	sub {
		say "Cnnection Error";
		$cv->send;
		exit;
	}
);
$cv->recv;
