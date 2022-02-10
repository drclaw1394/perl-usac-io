#!/usr/bin/env perl
#
use strict;
use warnings;
use feature qw<say signatures current_sub>;
no warnings "experimental";

use Mojo::IOLoop;
use Mojo::IOLoop::Stream;

my $read_size=$ARGV[0]//4096;
my $results=$ARGV[1]//"read-results.txt";

my %results;
sub do_mojo {
	my $label=shift;
	my $total=0;
	my $start_time=time;
	my $counter=5;
	my $end_time;
	my $calls=0;
	my $flag=0;

	unless ($read_size==131072){

		say STDERR "SKIPPING MOJO READ";
		if(open my $output, ">>", $results){
			say $output "$label 0 0";
		}
		return;
		
	}



	# Create stream
	my $stream = Mojo::IOLoop::Stream->new(*STDIN);
	$stream->on(read => sub ($stream, $bytes) {
			$calls++;
			$total+=length $bytes;
			if($flag){
				say length $bytes;
				$flag=0;
			}
			$end_time=time;
		});
	#$stream->on(close => sub ($stream) {...});
	$stream->on(error => sub ($stream, $err) {
			say "GOT ERROR"
		});

	# Start and stop watching for new data
	$stream->start;

	# Add a timer
	Mojo::IOLoop->timer(1 => sub ($loop) {
		unless ($counter--){
			$stream->stop;
			$stream->reactor->stop;
		}
		else {

			say STDERR "bytes read: $total";
			Mojo::IOLoop->timer(1=>__SUB__);
		}
	}); 


	# Start reactor if necessary
	$stream->reactor->start unless $stream->reactor->is_running;
	my $rate=$total/($end_time-$start_time);
	$results{$label}=$rate;
	say STDERR "bytes per second: ", $rate;
	if(open my $output, ">>", $results){
		say $output "$label $rate $read_size";
	}
}

	do_mojo("mojo");

