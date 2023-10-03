package uSAC::IO;
use strict;
use warnings;
use feature "say";

our $VERSION="v0.1.0";

#Datagram
use Import::These qw<uSAC::IO:: DReader DWriter SWriter SReader>;


#use Socket  ":all";
use Socket::More;
use IO::FD;




#use Exporter;# qw<import>;
use Export::These;

######################################################
# sub import {                                       #
#         Socket->export_to_level(1, undef, ":all"); #
#                                                    #
# }                                                  #
######################################################

sub _reexport {
#Socket->import(":all");
}

use Net::DNS::Native;

our $resolver=Net::DNS::Native->new(pool=>5, notify_on_begin=>1);

#asynchronous bind for tcp, udp, and unix sockets

use uSAC::IO::Common;
my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::IO");

die "Could not require $rb" unless(eval "require $rb");

no strict "refs";

our $Clock=time;



sub asap (&);   # Schedule sub as soon as async possible
sub timer ($$$);  # Setup a timer
sub timer_cancel ($);
sub connect_cancel ($);
sub connect_addr;


*asap=\&{$rb."::asap"};
*timer=\&{$rb."::timer"};
*timer_cancel=\&{$rb."::timer_cancel"};
*connect_cancel=\&{$rb."::connect_cancel"};
*connect_addr=\&{$rb."::connect_addr"};

# Start a 1 second tick timer. This simply updates the 'clock' used for simple
# timeout measurements.
our $Tick_Timer=timer 0, 1, sub { $Clock=time; };

use strict "refs";
#Create a socket with required family, type an protocol
#No bound or connected to anything
#A wrapper around IO::FD::socket
#######################################
# sub socket {                        #
#         my $socket;                 #
#         IO::FD::socket $socket, @_; #
#         $socket;                    #
# }                                   #
#                                     #
#######################################
#Bind a socket to a host, port  or unix path. The host and port are strings
#Which are attmped to be converted to address structures applicable for the
#socket type Returns the address structure created Does not perform name
#resolving. you need to to know the address of the interface you wish to use
#A special case of localhost is resolved to the loopback devices appropriate to
#the family of the socket
#my ($package, $socket, $host, $port, $on_bind, $on_error)=@_;
sub bind{
	my ($socket, $host, $port)=@_;

	my $fam= sockaddr_family IO::FD::getsockname $socket;

	die  "Not a socket" unless defined $fam;

	my $type=unpack "I", IO::FD::getsockopt $socket, SOL_SOCKET, SO_TYPE;

	say "Family is $fam, type is $type";
	say AF_INET;
	say SOCK_DGRAM;
	my $addr;

	if($fam==AF_INET or $fam==AF_INET6){
		my @addresses;
		my $ok;
		my $flags=AI_PASSIVE;
		$flags|=AI_NUMERICHOST if $host eq "localhost";
			#Convert to address structures. DO NOT do a name lookup
		  $ok=getaddrinfo(
			$host,
			$port,
			{
				flags=>$flags,
				family=>$fam,
				type=>$type
			},
      @addresses

		);

		die gai_strerror($!) unless $ok;

		my ($target)= grep {
			$_->{family} == $fam	#Matches INET or INET6
			#and $_->{socktype} == $type #Stream/dgram
			} @addresses;
		$addr=$target->{addr};
	}
	elsif($fam==AF_UNIX){
		$addr=pack_sockaddr_un $host;
	}
	else {
		die "Unsupported socket address family";
	}
	IO::FD::bind($socket, $addr) and $addr;
}




sub connect{
	my ($socket, $host, $port, $on_connect, $on_error)=@_;
	my $fam= sockaddr_family IO::FD::getsockname $socket;

  unless(defined $fam){
    # TODO:  create an exception object
    $on_error and asap { $on_error->($socket, "Not a socket")};
    return undef;
  }

	my $type=unpack "I", IO::FD::getsockopt $socket, SOL_SOCKET, SO_TYPE;

	my $ok;
	my @addresses;
	my $addr;

	if($fam==AF_INET or $fam==AF_INET6){
		#Convert to address structures. DO NOT do a name lookup
		$ok=getaddrinfo(
			$host,
			$port,
			{
        #flags=>$host eq "localhost"? 0 : AI_NUMERICHOST,
				family=>$fam,
				socktype=>$type
			},
      @addresses

		);

    unless($ok){
      $on_error and asap { $on_error->($socket, gai_strerror $!)};
      return undef;
    }

    $addr=$addresses[0]{addr};
	}
	elsif($fam==AF_UNIX){
		$addr=pack_sockaddr_un $host;
	}
	else {
    #die "Unsupported socket address family";
    $on_error and asap sub { $on_error->($socket, "Unsupported socket address family")};
    return undef;
	}

	connect_addr($socket, $addr, $on_connect, $on_error);
}



#Resolve a hostname to an address, then connect to it
sub resolve_connect{
	Net::DNS->resolve;
}


sub dreader {
	&uSAC::IO::DReader::create;
}
sub sreader {
	&uSAC::IO::SReader::create;
}

sub dwriter {
	&uSAC::IO::DWriter::create;
}
sub swriter {
	&uSAC::IO::SWriter::create;
}






#Return a writer based on the type of fileno
sub writer {

	my @stat=IO::FD::stat $_[0];
	if(-p $_[0]){
		#Is a pipe
		return &swriter;
	}
	elsif(-S $_[0]){
		#Is a socket
		for(unpack "I", IO::FD::getsockopt $_[0], SOL_SOCKET, SO_TYPE){
			if($_==SOCK_STREAM){
				return &swriter;
			}
			elsif($_==SOCK_DGRAM){
				return &dwriter;
			}
			elsif($_==SOCK_RAW){
				die "RAW SOCKET NOT IMPLEMENTED";
			}
			else {
				die "Unkown socket type";
			}
		}
	}
	else {
		#OTHER?
		#TODO: fix this
		return &swriter;
	}
}

sub reader{
	my @stat=IO::FD::stat $_[0];
	if(-p $_[0]){
		#PIPE
		return &sreader;
	}
	elsif(-S $_[0]){
		#SOCKET
		for(unpack "I", IO::FD::getsockopt $_[0], SOL_SOCKET, SO_TYPE){
			if($_ == SOCK_STREAM){
				return &sreader;
			}
			elsif($_ == SOCK_DGRAM){
				return &dreader;
			}
			elsif($_ == SOCK_RAW){
				die "RAW SOCKET NOT IMPLEMENTED";
			}
			else {
				die "Unkown socket type";
			}
		}
	}
	else {
		#OTHER
		#TODO: fix this
		return &sreader;
	}
}

sub pair {
	my ($fh)=@_;
	my ($r,$w)=(reader(fh=>$fh), writer(fh=>$fh));
	$r and $w ? ($r,$w):();
}

sub pipe {
	my ($rfh,$wfh)=@_;
	my ($r,$w)=(reader($rfh), writer($wfh));
	if($r and $w){
		$r->pipe($w);
		return ($r,$w);	
	}
	();
	
}


###########################################
# my %timers;                             #
# sub timer  {                            #
#   my ($package, $offset, $interval)=@_; #

# }                                       #
# sub cancel_timer {                      #
#   my $id;                               #
# }                                       #
###########################################







1;

__END__

=head1 NAME

uSAC::IO - Multibackend IO

=head1 SYNOPSIS

	use uSAC::IO;

	my $reader=uSAC::IO->reader(STDIN);
	my $reader=uSAC::IO->reader($my streaming_socket)

=head1 Description

Provides a streamlined interface for asynchronous IO, using an event loop you
already use. Implements a common interface between stream and datagram sockets,
pipes etc.

Think of this module as subclass of IO::Handle  or AnyEvent::Handle etc, but
has better performance and runs on multiple event loops

Care has been taken in keeping memory usage low and throuput high.


=head1 HOW IT WORKS

When this module is loaded, it detects an already loaded IO loop, and
subsequently loads the appropriate backend to implement the API.


