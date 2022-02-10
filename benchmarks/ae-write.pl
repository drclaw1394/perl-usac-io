use strict;
use warnings;
use feature ":all";

use EV;
use AnyEvent::Handle;
use AnyEvent;
use Time::HiRes qw<time>;
my %results;

#read for time 
my $fh=*STDOUT;
my $data="a"x ($ARGV[0]//4096);#128;
my $results=$ARGV[1]//"write-results.txt";


sub do_ae {
	my $label=shift;
	my $total=0;
	my $cv=AE::cv;
	my $counter=5;
	my $ae; $ae=AnyEvent::Handle->new(fh=>$fh, @_);#read_size=>4096, autocork=>undef);

	my $timer;
	$timer=AE::timer 1, 1, sub {
		unless ($counter--){

			#$ae->on_read();
			$ae=undef;
			$timer=undef;
			$cv->send;
		}

		else {

			say STDERR "bytes written: $total";
		}
	};

	my $start_time=time;
	my $end_time;
	$ae->push_write($data);
	$ae->on_drain(sub {
			$total+=length $data;
			$end_time=time;
			my $timer;$timer=AE::timer 0.0,0, sub {
				$ae->push_write($data);
				$timer=undef;
			};
		});

	$cv->recv;
	my $rate=$total/($end_time-$start_time);
	$results{$label}=$rate;

	say STDERR "bytes per second: ", $rate;
	if(open my $output, ">>", $results){
		say $output "$label $rate ".length($data);
	}
		
}

do_ae("ae-nocork", autocork=>undef);
#do_ae("ae-cork", autocork=>1);

my @keys= sort keys %results;
local $,=", ";
say STDERR @keys;
for my $row (@keys){
	my $base=$results{$row};
	say STDERR $row;
	say STDERR map { $results{$_}/$base } (@keys)
}
