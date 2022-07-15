use strict;
use warnings;
use feature ":all";

use Test::More;

use AnyEvent;

#use uSAC::IO::AE::DReader;
use uSAC::IO::AE::DReader;
use uSAC::IO::AE::DWriter;
use uSAC::IO::AE::SWriter;
use uSAC::IO::AE::SReader;
use uSAC::IO;

my $cv=AE::cv;

my $port=5050;
my $host="127.0.0.1";

my $fh=IO::Socket->new(
	Domain=>AF_INET,
	Proto=>"udp", 
	Blocking=>undef,
	ReusePort=>1,
	ReuseAddr=>1
);

uSAC::IO->connect_inet(
	$fh,
	$host,
	$port,
	sub {
		say $_[0];
		my $reader=uSAC::IO::AE::DReader->new(rfh=>$_[0]);

		my $writer=uSAC::IO::AE::SWriter->new(wfh=>\*STDOUT);
		$reader->pipe($writer);
		$reader->start;

		my $dwriter=uSAC::IO::AE::DWriter->new(wfh=>$_[0]);
		my $stdin=uSAC::IO::AE::SReader->new(rfh=>\*STDIN);
		$stdin->pipe($dwriter);
		$stdin->start;
	},

	sub {
		die "$!";
	}
);
$cv->recv;
