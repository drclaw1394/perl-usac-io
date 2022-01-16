use strict;
use warnings;
use feature ":all";

use EV;
use AnyEvent;

use uSAC::DWriter;
use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in inet_aton>;
use Time::HiRes qw<time>;

my %results;

#read for time 
my $data="hello"x ($ARGV[0]//2096);#128;

sub do_usac {
	my $label=shift;
	my $cv=AE::cv;
	socket my $fh, AF_INET, SOCK_DGRAM, 0;
	my $addr=pack_sockaddr_in 8080, inet_aton "192.168.1.110";
	say $! unless connect $fh, $addr;

	my $total=0;
	my $start_time=time;
	my $counter=5;
	my $end_time;
	my $timer;

	my $writer=uSAC::DWriter->new(undef, $fh);
	$writer->on_error=sub {
		say "Got Error: $!";
		say "exiting";
		exit;
	};

	$timer=AE::timer 1, 1, sub {
		say STDERR "TIMER";
		unless ($counter--){
			$writer->pause;	
			$timer=undef;
			$cv->send;
		}
		else {

			say STDERR "bytes written: $total";
		}

	};

	#write and wait for empty
	sub {
		$total+=length $data;
		$end_time=time;
		my $self=__SUB__;
		my $timer;$timer=AE::timer 0.0, 0, sub {
			$writer->write($data,$self);
			$timer=undef;
		};

	}->();

	#$writer->start;

	$cv->recv;
	$results{$label}=$total/($end_time-$start_time);

	say STDERR "bytes per second: ", $total/($end_time-$start_time);

}


do_usac("usac");

my @keys= sort keys %results;
local $,=", ";
say STDERR @keys;
for my $row (@keys){
	my $base=$results{$row};
	say STDERR $row;
	say STDERR map { $results{$_}/$base } (@keys)
}
