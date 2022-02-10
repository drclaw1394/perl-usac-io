#!/usr/bin/env perl
use strict;
use warnings;
use feature ":all";
no warnings "experimental";

use EV;
use AnyEvent;
use uSAC::SIO;
use Time::HiRes qw<time>;

my %results;

my $read_size=$ARGV[0]//4096;
my $results=$ARGV[1]//"read-results.txt";

sub do_usac {
	#read for time 
	my $label=shift;
	my $cv=AE::cv;
	my $fh=*STDIN;
	my $timer;
	
	my $total=0;
	my $counter=5;
	my $end_time;
	my $flag=0;
	my $calls=0;
	my $reader=uSAC::SIO->new(undef, $fh);
	$reader->max_read_size=$read_size;
	$reader->on_read=sub {
		$calls++;
		$total+=length $_[1];
			if($flag){
				say length $_[1];
				$flag=0;
			}
		$_[1]="";

		$end_time=time;
	};

	$timer=AE::timer 1, 1, sub {
		unless ($counter--){
			$reader->pause;	
			$timer=undef;
			$cv->send;
		}
		else {
			$flag=1;
			say "bytes read: $total";
		}
	};

	$reader->start;

	my $start_time=time;
	$cv->recv;
	my $rate=$total/($end_time-$start_time);
	$results{$label}=$rate;
	say STDERR "bytes per second: ", $rate;
	if(open my $output, ">>", $results){
		say $output "$label $rate $read_size";
	}
}
do_usac("usac");
