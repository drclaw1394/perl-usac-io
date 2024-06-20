package uSAC::IO;
use strict;
use warnings;
use feature "say";

our $VERSION="v0.1.0";

#Datagram
use Import::These qw<uSAC::IO:: DReader DWriter SWriter SReader>;


use Socket::More;
use Socket::More::Resolver {}, undef;
use IO::FD::DWIM ();
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK :mode);




use Export::These qw{asap timer timer_cancel connect connect_cancel connect_addr bind pipe pair dreader dwriter reader writer sreader swriter signal};


sub _reexport {
}



#asynchronous bind for tcp, udp, and unix sockets

use uSAC::IO::Common;
my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::IO");

die "Could not require $rb" unless(eval "require $rb");

no strict "refs";

our $Clock=time;


# Must return 1
# Takes a sub as first argument, remaining arguments are passed to sub
sub asap (*@);   # Schedule sub as soon as async possible

# Must return an integer key for the timer.
sub timer ($$$);  # Setup a timer

sub signal ($$);  #Assign a signal handler to a signal

# Must delete the timer from store
# Must use alias of argument to make undef
sub timer_cancel ($);
sub connect_cancel ($);
sub connect_addr;
sub _pre_loop;
sub _post_loop;
sub _shutdown_loop;


*asap=\&{$rb."::asap"};                         # Schedual code to run as soon as possible (next tick)
*signal=\&{$rb."::signal"};                         # Schedual code to run as soon as possible (next tick)
*signal_cancel=\&{$rb."::signal_cancel"};                         # Schedual code to run as soon as possible (next tick)
*timer=\&{$rb."::timer"};                       # Create a timer, with offset, and repeat, returns ref
*timer_cancel=\&{$rb."::timer_cancel"};         # cancel a timer
*connect_cancel=\&{$rb."::connect_cancel"};     # Cancel a connect
*connect_addr=\&{$rb."::connect_addr"};         # Connect via address structure


*CORE::GLOBAL::exit=\&{$rb."::_exit"};          # Make global exit shutdown the loop 


*_pre_loop=\&{$rb."::_pre_loop"};               # Internal
*_post_loop=\&{$rb."::_post_loop"};             # Internal
*_shutdown_loop=\&{$rb."::_shutdown_loop"};     # Internal



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

sub fd_2_fh {
  my $socket=$_[0];
  unless(ref $socket){
    # Convert to a filehandle to work with built in perl test functions
    open($socket, "<&=", $socket)
  }
  else {
    #Assume it is already a perl file handle and 
  }
  $socket;
}

sub bind ($$$;$&&) {
  my ($socket, $host, $port, $spec, $on_bind, $on_error)=@_;

  # TODO: First check if hints is a scalar, and parse into spec
  my $hints=$spec; 
  
  my $fam;
  my $type;
  my $protocol;

  if(!defined $socket){
    my $res=IO::FD::socket $socket, $fam=$hints->{family}, $type=$hints->{type}, $protocol=$hints->{protocol}//0;
    unless ($res){
      $on_error && asap $on_error, $!;
      return;
    }
    # set socket to non block mode as we are async library ;)
    # TODO open a socket with platform specific flags to avoid this extra call
    $res= IO::FD::fcntl $socket, F_SETFL, O_NONBLOCK;
    unless (defined $res){
      $on_error && asap $on_error, $!;
    }
  }
  else {
    # Get filedescriptor if not  a filedescriptor
    #$socket=fileno($socket) if ref $socket;
  }

  
  #my $fam= sockaddr_family IO::FD::DWIM::getsockname $socket;
  #die  "Not a socket" unless defined $fam;
  #my $type=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
  my $addr;

  $type=$hints->{socktype}//=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
  $fam=$hints->{family}//=sockaddr_family IO::FD::DWIM::getsockname $socket;

  $hints->{port}//=$port;
  $hints->{address}//=$host;
  $hints->{type}=$hints->{socktype};
  use Data::Dumper;
  say "HINTS: ".Dumper $hints;
  #IP_RECVIF on mac os?
  #IP_BOUNDIF
  #SO_BINDTODEVICE on linux
  #Create the address strucure we need
  my @res=Socket::More::sockaddr_passive $hints;
  say "after";
  for (@res){
    say "LOOP: ".$_;
    say Dumper $_;
    my $addr=$_->{addr};
    if(IO::FD::DWIM::bind($socket, $addr)){
      say "BIND OK $addr";
      $on_bind and $on_bind->($socket, $addr);
    }
    else {
      say "ERROR: ". $!;
      my $err=$!;
       $on_error and $on_error->($socket, $err);
    }
  }

  #################################################################################
  # if($fam==AF_INET or $fam==AF_INET6){                                          #
  #   my $ok;                                                                     #
  #   my $flags=AI_PASSIVE;                                                       #
  #   $flags|=AI_NUMERICHOST if $host eq "localhost";                             #
  #   #Convert to address structures. DO NOT do a name lookup                     #
  #   $ok=Socket::More::Resolver::getaddrinfo(                                    #
  #     $host,                                                                    #
  #     $port,                                                                    #
  #     {                                                                         #
  #       flags=>$flags,                                                          #
  #       family=>$fam,                                                           #
  #       type=>$type                                                             #
  #     },                                                                        #
  #                                                                               #
  #     sub {                                                                     #
  #       my ($target)= grep {                                                    #
  #         $_->{family} == $fam  #Matches INET or INET6                          #
  #         #and $_->{socktype} == $type #Stream/dgram                            #
  #       } @_;                                                                   #
  #                                                                               #
  #       $addr=$target->{addr};                                                  #
  #       if(IO::FD::DWIM::bind($socket, $addr)){                                 #
  #         say "BIND OK $addr";                                                  #
  #           $on_bind and $on_bind->($socket, $addr);                            #
  #       }                                                                       #
  #       else {                                                                  #
  #         my $err=$!;                                                           #
  #          $on_error and $on_error->($socket, $err);                            #
  #       }                                                                       #
  #     },                                                                        #
  #                                                                               #
  #     sub {                                                                     #
  #         $on_error and $on_error->($socket, gai_strerror $!);                  #
  #     }                                                                         #
  #   );                                                                          #
  # }                                                                             #
  # elsif($fam==AF_UNIX){                                                         #
  #   $addr=pack_sockaddr_un $host;                                               #
  #   if(IO::FD::DWIM::bind($socket, $addr)){                                     #
  #     say "BIND OK $addr";                                                      #
  #       $on_bind and asap $on_bind, $socket, $addr;                             #
  #   }                                                                           #
  #   else {                                                                      #
  #     my $err=$!;                                                               #
  #      $on_error and asap $on_error, $socket, $err;                             #
  #   }                                                                           #
  # }                                                                             #
  # else {                                                                        #
  #   #die "Unsupported socket address family";                                   #
  #   $on_error and asap $on_error, $socket, "Unsupported socket address family"; #
  #################################################################################
  #}

}



# TODO: allow a string as a spec to be used instead of hints? Only valid when host is undef.
# TODO: allow host and port (addr and po ) in spec when host and port are undef for spec processing
sub connect ($$$$;**){

	my ($socket, $host, $port, $hints, $on_connect, $on_error)=@_;
  #If socket is not defined, we attempt to create one
  my $fam;
  my $type;
  my $protocol;
  if(!defined $socket){
    my $res=IO::FD::socket $socket, $fam=$hints->{family}, $type=$hints->{socktype}, $protocol=$hints->{protocol}//0;
    unless ($res){
      say $!;
      $on_error && asap $on_error, $!;
      return;
    }
    # set socket to non block mode as we are async library ;)
    # TODO open a socket with platform specific flags to avoid this extra call
    $res= IO::FD::fcntl $socket, F_SETFL, O_NONBLOCK;
    unless (defined $res){
      $on_error && asap { $on_error->($!)};
    }
  }
  else {
    # Get filedescriptor if not  a filedescriptor
    #$socket=fileno($socket) if ref $socket;
  }

  #my $fam= sockaddr_family IO::FD::DWIM::getsockname $socket;

  #################################################################
  # unless(defined $fam){                                         #
  #   # TODO:  create an exception object                         #
  #   $on_error and asap { $on_error->($socket, "Not a socket")}; #
  #   return undef;                                               #
  # }                                                             #
  #################################################################

  #my $type=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
	my $ok;
	my $addr;


  # If the type and  family hasn't been specified with hints, extract from socket info
  $type=$hints->{socktype}//=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
  $fam=$hints->{family}//=sockaddr_family IO::FD::DWIM::getsockname $socket;

  #say STDERR sock_to_string $type;
  #say STDERR family_to_string $fam;


  #say STDERR time;
	if($fam==AF_INET or $fam==AF_INET6){
		#Convert to address structures. DO NOT do a name lookup
		$ok=Socket::More::Resolver::getaddrinfo(
			$host,
			$port,
      $hints,
      sub {
        my @addresses=@_;
        $addr=$addresses[0]{addr};
	      connect_addr($socket, $addr, $on_connect, $on_error);
        #say STDERR time;

      },

      sub{
        $on_error and $on_error->($socket, gai_strerror $!);
      }

		);


	}
	elsif($fam==AF_UNIX){
		$addr=pack_sockaddr_un $host;
	  connect_addr($socket, $addr, $on_connect, $on_error);
	}
	else {
    #die "Unsupported socket address family";
    $on_error and asap sub { $on_error->($socket, "Unsupported socket address family")};
    return undef;
	}

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

  my $socket=$_[0];
  my @stat=IO::FD::DWIM::stat $socket;
  my $mode=$stat[2];
	if(S_ISFIFO $mode){
		#Is a pipe
		return swriter fh=>$socket;
	}
	elsif(S_ISSOCK $mode){
		#Is a socket
		for(unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE){
			if($_==SOCK_STREAM){
				return swriter fh=>$socket;
			}
			elsif($_==SOCK_DGRAM){
				return dwriter fh=>$socket;
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
    say "OTHER SOCKET TYPE";
		#OTHER?
		#TODO: fix this
		return swriter fh=>$socket;
	}
}

sub reader{
  my $socket=$_[0];
  my @stat=IO::FD::DWIM::stat $socket;
  my $mode=$stat[2];

	if(S_ISFIFO $mode){
		#PIPE
		return sreader fh=>$socket;
	}
	elsif(S_ISSOCK $mode){
		#SOCKET
		for(unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE){
			if($_ == SOCK_STREAM){
				return sreader fh=>$socket
			}
			elsif($_ == SOCK_DGRAM){
				return dreader fh=>$socket;
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
		return sreader fh=>$socket;
	}
}

sub pair {
	my ($fh)=@_;
	my ($r, $w)=(reader(fh=>$fh), writer(fh=>$fh));
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


