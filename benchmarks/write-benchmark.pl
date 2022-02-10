use strict;
my $size=1;
`echo ""> write-results.txt`;

`perl -I lib benchmarks/usac-write.pl $size`;
`perl -I lib benchmarks/ae-write.pl $size`;
`perl -I lib benchmarks/mojo-write.pl $size`;

$size=128;
`perl -I lib benchmarks/usac-write.pl $size`;
`perl -I lib benchmarks/ae-write.pl $size`;
`perl -I lib benchmarks/mojo-write.pl $size`;

$size=1024;
`perl -I lib benchmarks/usac-write.pl $size`;
`perl -I lib benchmarks/ae-write.pl $size`;
`perl -I lib benchmarks/mojo-write.pl $size`;

$size=2048;
`perl -I lib benchmarks/usac-write.pl $size`;
`perl -I lib benchmarks/ae-write.pl $size`;
`perl -I lib benchmarks/mojo-write.pl $size`;

$size=4096;
`perl -I lib benchmarks/usac-write.pl $size`;
`perl -I lib benchmarks/ae-write.pl $size`;
`perl -I lib benchmarks/mojo-write.pl $size`;

$size=8192;
`perl -I lib benchmarks/usac-write.pl $size`;
`perl -I lib benchmarks/ae-write.pl $size`;
`perl -I lib benchmarks/mojo-write.pl $size`;

$size=16384;
`perl -I lib benchmarks/usac-write.pl $size`;
`perl -I lib benchmarks/ae-write.pl $size`;
`perl -I lib benchmarks/mojo-write.pl $size`;
