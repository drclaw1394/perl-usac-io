use strict;
use warnings;
use feature ":all";

use EV;
use uSAC::SIO;
use AnyEvent;
use Time::HiRes qw<time>;
my %results;

#read for time 
my $fh=*STDOUT;
my $data="a"x ($ARGV[0]//4096);#128;
my $results=$ARGV[1]//"write-results.txt";

sub do_usac {
	my $label=shift;
	my $cv=AE::cv;
	my $total=0;
	my $start_time=time;
	my $counter=5;
	my $end_time;
	my $timer;

	my $writer=uSAC::SIO->new(undef, $fh);

	$timer=AE::timer 1, 1, sub {
		say STDERR "TIMER";
		unless ($counter--){
			$writer->pause;	
			$timer=undef;
			$cv->send;
		}
		else {

			say STDERR "bytes written: $total";
		}

	};

	#write and wait for empty
	sub {
		$total+=length $data;
		$end_time=time;
		my $self=__SUB__;
		my $timer;$timer=AE::timer 0.0, 0, sub {
			$writer->write($data,$self);
			$timer=undef;
		};

	}->();

	#$writer->start;

	$cv->recv;
	my $rate=$total/($end_time-$start_time);
	$results{$label}=$rate;

	say STDERR "bytes per second: ", $rate;
	if(open my $output, ">>", $results){
		say $output "$label $rate ".length($data);
	}

}


do_usac("usac");
