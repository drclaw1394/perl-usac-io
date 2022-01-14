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
sub do_usac {
	#read for time 
	my $cv=AE::cv;
	my $fh=*STDIN;
	my $timer;
	
	$reader->max_read_size=$read_size;
	my $total=0;
	my $counter=5;
	my $end_time;
	my $flag=0;
	my $calls=0;
	my $reader=uSAC::SIO->new(undef, $fh);
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
	$results{usac}=$total/($end_time-$start_time);

	say "bytes per second: ", $total/($end_time-$start_time);
	say "Call count: $calls";
}

do_usac;
my @keys= sort keys %results;
local $,=", ";
for my $row (@keys){
	my $base=$results{$row};
	say STDERR $row;
	say STDERR map { $results{$_}/$base } (@keys)
}
