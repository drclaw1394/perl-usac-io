use strict;
use warnings;
use feature ":all";

use Test::More;

use AnyEvent;

#use uSAC::IO::AE::DReader;
use uSAC::IO::DReader;
use uSAC::IO::DWriter;
use uSAC::IO::SWriter;
use uSAC::IO::SReader;

my $cv=AE::cv;

my $port=5050;
my $host="localhost";

uSAC::IO::DReader->connect(
	$host,
	$port,
	sub {
		say $_[0];
		my $reader=uSAC::IO::DReader->new($_[0]);

		my $writer=uSAC::IO::SWriter->new(\*STDOUT);
		$reader->pipe($writer);
		$reader->start;

		my $dwriter=uSAC::IO::DWriter->new($_[0]);
		my $stdin=uSAC::IO::SReader->new(\*STDIN);
		$stdin->pipe($dwriter);
		$stdin->start;
	},

	sub {
		die "$!";
	}
);
$cv->recv;
