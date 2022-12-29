use strict;
use warnings;
use feature ":all";

use Test::More;

use AnyEvent;

use uSAC::IO;
#use uSAC::IO::SReader;
#use uSAC::IO::SWriter;

my $cv=AE::cv;
my $time=0;
my $clock=0;
my $reader=uSAC::IO->sreader(fh=>\*STDIN, time=>\$time, clock=>\$clock, on_read=>undef,on_eof=>undef,on_error=>undef, max_read_size=>4096, sysread=>undef);

my $writer=uSAC::IO->swriter(fh=>\*STDOUT, time=>\$time, clock=>\$clock,on_error=>undef, syswrite=>undef);

$reader->pipe_to($writer);

#my ($reader,$writer)=uSAC::IO->pipe(\*STDIN, \*STDOUT);
#say "Reader:  $reader";
#say  "Writer: $writer";
$reader->start if $reader;

say "START Typing...";
$cv->recv;
