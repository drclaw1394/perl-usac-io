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
my $data="hello"x ($ARGV[0]//2096);#128;


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
	$results{$label}=$total/($end_time-$start_time);
	say STDERR "bytes per second: ", $total/($end_time-$start_time);
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
