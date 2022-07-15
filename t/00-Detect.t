use strict;
use warnings;
use feature ":all";

use Test::More;

use AnyEvent;

use uSAC::IO::SReader;
use uSAC::IO::SWriter;

my $cv=AE::cv;

my $reader=uSAC::IO::SReader->sreader(rfh=>\*STDIN);
my $writer=uSAC::IO::SWriter->swriter(wfh=>\*STDOUT);

$reader->on_read=sub {
	$writer->write($_[0]);
};

$reader->start;

$cv->recv;


