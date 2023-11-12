package uSAC::IO::Common;
use strict;
use warnings;
#use Carp qw<carp>;


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
		warn "No event system detected. defaulting to AE";
		#set default to any event
		$backend="uSAC::IO::AE";
	}

	$backend;
}
1;
__END__

=head1 NAME

uSAC::IO::Common

=head1 DESCRIPTION

Provides internal functionallity. Currently implements detection of the current
event loop system. Supported event loops are AnyEvent, IOAsync, and IOMojo



