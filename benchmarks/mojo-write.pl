#!/usr/bin/env perl
use strict;
use warnings;
use feature qw<:all>;#qw<say signatures current_sub>;
no warnings "experimental";
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use Mojo::IOLoop;
use Mojo::IOLoop::Stream;
use Time::HiRes qw<time>;

my %results;

my $fh=*STDOUT;
my $data="hello"x ($ARGV[0]//2096);#128;
sub do_mojo {
	my $label=shift;
	my $total=0;
	my $start_time=time;
	my $counter=5;
	my $end_time;
	my $calls=0;
	my $flag=0;

	fcntl $fh, F_SETFL, O_NONBLOCK;
	# Create stream
	my $stream = Mojo::IOLoop::Stream->new($fh);
	$stream->on(error => sub {
			say "Got error";
		});
	$stream->on(drain => sub ($stream) {
			$calls++;
			$total+=length $data;
			$end_time=time;
			Mojo::IOLoop->next_tick(sub {
					$stream->write($data);
				});
		});

	$stream->start;

	# Add a timer
	Mojo::IOLoop->timer(1 => sub ($loop) {
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
