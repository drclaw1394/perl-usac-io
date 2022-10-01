use strict;
use v5.36;
my @size=(1, 128, 1024, 2048, 4096, 8192, 16384, 65536, 131072);
`echo ""> read-results.txt`;
for my $size(@size){
	say STDERR "READ SIZE: $size";

	`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
	`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
	`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;

}
