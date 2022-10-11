use strict;
use warnings;
use feature ":all";

use Test::More;


use uSAC::IO;

my $cv=AE::cv;

my $reader=uSAC::IO->reader(fh=>fileno STDIN);
my $writer=uSAC::IO->writer(fh=>fileno STDOUT);

$reader->on_read=sub {
	$writer->write($_[0]);
	$_[0]="";
};

#$reader->start;

#$cv->recv;


