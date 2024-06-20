use v5.36;
use strict;
my $size=1;
my @size=(1,128, 1024, 2048, 4096, 8192, 16384);

`echo ""> write-results.txt`;
for my $size(@size){

	`usac -I lib _--backend AnyEvent ./benchmarks/usac-write.pl $size`;
	`perl -I lib benchmarks/ae-write.pl $size`;
	`perl -I lib benchmarks/mojo-write.pl $size`;

}
