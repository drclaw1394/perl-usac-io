use uSAC::IO;
use feature ":all";

uSAC::IO::_make_pool(10);
my $counter=0;
my $root=$ARGV[0]//"";
asay $STDERR, "ROOT IS $root";
#timer 0, 0.02, sub {asay $STDERR, time};

my $s;
$s=sub {
	say STDERR "ABOUT TO CALL path_create";
	my $end;
	my $start=time;


	path_create "$root/testing/make/path", undef, sub {
		$end=time;
		adump $STDERR, "Results and error ", @_;
		say STDERR "CREATE PATH TOOK @{[$end-$start]} seconds";
		$s->();
		#timer 0.1, 0, $s;
	}, 
	sub {};
};
$s->();
