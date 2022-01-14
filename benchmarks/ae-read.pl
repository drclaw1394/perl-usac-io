#!/usr/bin/env perl
use strict;
use warnings;
use feature ":all";

use EV;
use uSAC::SIO;
use AnyEvent::Handle;
use AnyEvent;
use Time::HiRes qw<time>;
my %results;

my $read_size=$ARGV[0]//4096;

sub do_ae{
	my$total=0;
	my$cv=AE::cv;
	my $fh=*STDIN;
	my$counter=5;
	my $end_time;
	my $start_time;
	my $timer;
	my $flag=0;
	my $calls=0;
	my $ae; $ae=AnyEvent::Handle->new(fh=>$fh, max_read_size=> $read_size, read_size=>$read_size,  on_read=>sub {
			$calls++;
			$total+=length $ae->{rbuf};
			if($flag){
				say length $ae->{rbuf} ;
				$flag=0;
			}
			$ae->{rbuf}="";
			$end_time=time;
		});
	$timer=AE::timer 1, 1, sub {
		unless ($counter--){
			$ae->on_read(); #clear reader callback
			$ae=undef;
			$timer=undef;
			$cv->send;
		}
		else {

			say "bytes read: $total";
			$flag=1;
		}

	};

	$start_time=time;

	$cv->recv;
	$results{ae}=$total/($end_time-$start_time);

	say "bytes per second: ", $total/($end_time-$start_time);
	say "Call count: $calls";

}
do_ae;

my @keys= sort keys %results;
local $,=", ";
for my $row (@keys){
	my $base=$results{$row};
	say STDERR $row;
	say STDERR map { $results{$_}/$base } (@keys)
}
