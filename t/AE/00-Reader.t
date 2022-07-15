use strict;
use warnings;
use feature ":all";

use Test::More;

use AnyEvent;

use uSAC::IO::AE::SReader;
use uSAC::IO::AE::SWriter;

my $cv=AE::cv;

my $reader=uSAC::IO::AE::SReader->new(rfh=>\*STDIN);
my $writer=uSAC::IO::AE::SWriter->new(wfh=>\*STDOUT);

$reader->on_read=sub {
	$writer->write($_[0]);
};

$reader->start;

$cv->recv;


