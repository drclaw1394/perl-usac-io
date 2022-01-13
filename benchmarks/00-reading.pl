use strict;
use warnings;
use feature ":all";

use uSAC::SIO;
use AnyEvent::Handle;
use AnyEvent;
use Time::HiRes qw<time>;
my %results;

#read for time 
my $cv=AE::cv;
my $fh=*STDIN;
my $timer;
my $reader=uSAC::SIO->new(undef, $fh);

my $total=0;
my $start_time=time;
my $counter=5;
my $end_time;
$timer=AE::timer 1, 1, sub {
	unless ($counter--){
		$reader->pause;	
		$timer=undef;
		$cv->send;
	}
	else {

		say "bytes read: $total";
	}
	
};
$reader->on_read=sub {
	$total+=length $_[1];
	$_[1]="";

	$end_time=time;
};

$reader->start;

$cv->recv;
$results{usac}=$total/($end_time-$start_time);

say "bytes per second: ", $total/($end_time-$start_time);



$total=0;
$cv=AE::cv;
$counter=5;
my $ae; $ae=AnyEvent::Handle->new(fh=>$fh, read_size=>4096,  on_read=>sub {
	$total+=length $ae->{rbuf};
	$ae->{rbuf}="";

	$end_time=time;
});
$timer=AE::timer 1, 1, sub {
	unless ($counter--){

		$ae->on_read();
		$ae=undef;
		$timer=undef;
		$cv->send;
	}
	else {

		say "bytes read: $total";
	}
	
};

$start_time=time;

$cv->recv;
$results{ae}=$total/($end_time-$start_time);
say "bytes per second: ", $total/($end_time-$start_time);

my @keys= sort keys %results;
local $,=", ";
for my $row (@keys){
	my $base=$results{$row};
	say STDERR $row;
	say STDERR map { $results{$_}/$base } (@keys)
}
