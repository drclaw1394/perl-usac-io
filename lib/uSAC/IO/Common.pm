package uSAC::IO::Common;
use strict;
use warnings;
use Carp qw<carp>;


sub detect_backend{
	my $backend;
	if(exists $main::{"AnyEvent::"}){
		$backend="uSAC::IO::AE";
	}
	elsif(exists $main::{"IOASync::"}){
		#...
	}
	elsif(exists $main::{"IOMojo::"}){
		#...
	}
	else {
		carp "No event system detected. defaulting to AE";
		#set default to any event
		$backend="uSAC::IO::AE";
	}

	$backend;
}
1;
