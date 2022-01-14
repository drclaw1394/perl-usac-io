#!/usr/bin/env perl
#
use strict;
use warnings;

use Mojo::IOLoop;
use Mojo::IOLoop::Stream;
use feature qw<say signatures current_sub>;
no warnings "experimental";
my %results;
sub do_mojo {
	my $label=shift;
	my $total=0;
	my $start_time=time;
	my $counter=5;
	my $end_time;
	my $calls=0;
	my $flag=0;
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
		say STDERR "TIMER";
		unless ($counter--){
			$stream->stop;
			$stream->reactor->stop;
		}
		else {

			say STDERR "bytes written: $total";
			Mojo::IOLoop->timer(1=>__SUB__);
		}
	}); 


	# Start reactor if necessary
	$stream->reactor->start unless $stream->reactor->is_running;

	$results{mojo}=$total/($end_time-$start_time);
	say "bytes per second: ", $total/($end_time-$start_time);
	say "Call count: $calls";
}
do_mojo;
