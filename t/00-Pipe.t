use strict;
use warnings;
use feature ":all";

use Test::More;

use AnyEvent;

use uSAC::IO;
#use uSAC::IO::SReader;
#use uSAC::IO::SWriter;

my $cv=AE::cv;

my $reader=uSAC::IO->sreader(fh=>\*STDIN);
my $writer=uSAC::IO::SWriter->swriter(fh=>\*STDOUT);

$reader->pipe($writer);
$reader->start;

$cv->recv;
