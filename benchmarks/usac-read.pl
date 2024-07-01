#!/usr/bin/env perl
use strict;
use warnings;
use feature ":all";
no warnings "experimental";

use Time::HiRes qw<time>;

#use uSAC::IO;
my %results;

my $read_size=$ARGV[0]//4096;
my $results=$ARGV[1]//"read-results.txt";
my $start_time;

sub do_usac {
	#read for time 
	my $label=shift;
	my $fh=*STDIN;
	
	my $total=0;
	my $counter=5;
	my $end_time;
	my $flag=0;
	my $calls=0;
	my $reader=uSAC::IO::reader(fileno($fh));

	$reader->max_read_size=$read_size;
	$reader->on_read=sub {
		$calls++;
		$total+=length $_[0];
			if($flag){
				say length $_[0];
				$flag=0;
			}
		$_[0]="";

		$end_time=time;
	};

	uSAC::IO::timer 1, 1, sub {
		unless ($counter--){
			$reader->pause;	
      &uSAC::IO::timer_cancel;
      my $rate=$total/($end_time-$start_time);
      $results{$label}=$rate;
      say STDERR "bytes per second: ", $rate;
      if(open my $output, ">>", $results){
        say $output "$label $rate $read_size";
      }
      exit;
		}
		else {
			$flag=1;
			say "bytes read: $total";
		}
	};

	$reader->start;

	$start_time=time;
}

do_usac("usac");
