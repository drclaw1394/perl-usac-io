use strict;
my $size=1;
`echo ""> read-results.txt`;

`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;

$size=128;
`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;

$size=1024;
`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;

$size=2048;
`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;

$size=4096;
`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;

$size=8192;
`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;

$size=16384;
`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;

$size=65536;
`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;

$size=131072;
`cat /dev/zero | perl -I lib benchmarks/usac-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/ae-read.pl $size`;
`cat /dev/zero | perl -I lib benchmarks/mojo-read.pl $size`;
