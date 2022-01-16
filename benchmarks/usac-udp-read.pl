#!/usr/bin/env perl
use strict;
use warnings;
use feature ":all";
no warnings "experimental";

use EV;
use AnyEvent;
use uSAC::DReader;
use Time::HiRes qw<time>;
use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in inet_aton>;

my %results;

my $read_size=$ARGV[0]//4096;
sub do_usac {
	#read for time 
	my $cv=AE::cv;
	socket my $fh, AF_INET, SOCK_DGRAM, 0;
	my $addr=pack_sockaddr_in 8080, inet_aton "localhost";
	bind 	$fh, $addr;
	my $timer;
	
	my $total=0;
	my $counter=5;
	my $end_time;
	my $flag=0;
	my $calls=0;
	my $reader=uSAC::DReader->new(undef, $fh);
	$reader->max_read_size=$read_size;
	$reader->on_message=sub {
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
