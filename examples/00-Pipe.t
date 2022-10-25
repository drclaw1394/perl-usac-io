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
my $writer=uSAC::IO->swriter(fh=>\*STDOUT);

$reader->pipe_to($writer);

#my ($reader,$writer)=uSAC::IO->pipe(\*STDIN, \*STDOUT);
#say "Reader:  $reader";
#say  "Writer: $writer";
$reader->start if $reader;

$cv->recv;
