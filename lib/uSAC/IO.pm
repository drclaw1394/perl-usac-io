package uSAC::IO;
use strict;
use warnings;

use feature "say";
use feature "current_sub";

our $VERSION="v0.1.0";

#Datagram
use Import::These qw<uSAC::IO:: DReader DWriter SWriter SReader>;


use Socket::More;
use Socket::More::Resolver {}, undef;
use IO::FD::DWIM ();
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK :mode);

use Data::Dumper;



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


# Create a socket from hints and call the indicated callback ( or override when done)
# 
sub _create_socket {
  # Hints are in first argument
  my ($socket, $hints, $override)=@_;
  return undef if defined $socket;

  say STDERR "_create_socket called";
  for($hints){
    my $on_error=$_->{data}{on_error};
    my $on_socket=$override//$_->{data}{on_socket};

    if(defined IO::FD::socket $socket, $_->{family}, $_->{socktype}, $_->{protocol}//0){
      # set socket to non block mode as we are async library ;)
      # TODO open a socket with platform specific flags to avoid this extra call
      my $res= IO::FD::fcntl $socket, F_SETFL, O_NONBLOCK;
      unless (defined $res){
        say STDERR "ERROR in fcntl";
        $on_error && asap $on_error, $socket, $!;
        return;
      }
      $on_socket and asap $on_socket, $socket, $_;
    }
    else {
      # First argument is a socket that doesnt exist
      $on_error and asap $on_error, undef, $!;
    }
  }

  # ensure a true return value
  #
  return 1;
}

# Create sockets based on specs
#  spec, and callbacks
#
sub socket_stage ($$){
  my ($spec, $next)=@_;

  if(!ref $spec){
    # Assume string which needs parsing
    $spec=parse_passive_spec $spec;
  }

  #TODO merge spec with merge items
  
  # Generate a list of hints from the spec 
  my @res=sockaddr_passive $spec;

  # Start of the stages by creating a socket and calling on_socket
  _create_socket undef, $_, $next for(@res);
}


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

# Take a socket and the hints associated with it, binds to info from hints
# If socket doesn't exitst, one is created and this function recalled
# The socket and hints are passed to the callback on_bind
sub bind ($$) {

  say STDERR "BIND CALLED";
  my ($socket, $hints)=@_;

  _create_socket $socket, $hints, __SUB__  and return;

  my $fam;
  my $type;
  my $protocol;
  
  my $addr;

  my $on_bind=$hints->{data}{on_bind};
  my $on_error=$hints->{data}{on_error};
  say STDERR "SOcket is: $socket";
  $type=$hints->{socktype}//=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
  $fam=$hints->{family}//=sockaddr_family IO::FD::DWIM::getsockname $socket;

  for ($hints){
    my %copy=%$_; # Copy the spec?
    my $addr=$copy{addr};
    if(IO::FD::DWIM::bind($socket, $addr)){
      my $name=IO::FD::DWIM::getsockname $socket;
      $copy{addr}=$name;

      # Reify the port number now that a bind has taken place
      if($copy{family}==AF_INET or $copy{family}==AF_INET6){
          my $ok=Socket::More::Lookup::getnameinfo($name, my $host="", my $port="", NI_NUMERICHOST|NI_NUMERICSERV);
          if(defined $ok){
            $copy{port}=$port;
          }
      }
      say STDERR "Call on_bind", $on_bind;
      $on_bind and $on_bind->($socket, \%copy);
    }
    else {
      say STDERR "ERROR: ". $!;
      my $err=$!;
       $on_error and $on_error->($socket, $err);
    }
  }


}



# TODO: allow a string as a spec to be used instead of hints? Only valid when host is undef.
# TODO: allow host and port (addr and po ) in spec when host and port are undef for spec processing
sub connect ($$){
  say STDERR "Connect called";
	my ($socket, $hints)=@_;
  my $fam;
  my $type;
  my $protocol;

  my $on_connect=$hints->{data}{on_connect};
  my $on_error=$hints->{data}{on_error};

  my $host=$hints->{address};
  my $port=$hints->{port};

	my $ok;
	my $addr;

  _create_socket $socket, $hints, __SUB__ and return;

  # If the type and  family hasn't been specified with hints, extract from socket info
  $type=$hints->{socktype}//=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
  $fam=$hints->{family}//=sockaddr_family IO::FD::DWIM::getsockname $socket;

	if($fam==AF_INET or $fam==AF_INET6){
		#Convert to address structures. DO NOT do a name lookup
		$ok=Socket::More::Resolver::getaddrinfo(
			$host,
			$port,
      undef, #$hints,
      sub {
        say STDERR "LOOKUP callback"; 
        my @addresses=@_;
        $addr=$addresses[0]{addr};
	      connect_addr($socket, $addr, $on_connect, $on_error);
        say STDERR time;
      },

      sub{
        say STDERR "LOOKUP ERROR"; 
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
    $on_error and asap $on_error, $socket, "Unsupported socket address family";
	}
}

sub listen ($$){
  say STDERR "Listen called";
  my ($socket, $hints)=@_;

  _create_socket $socket, $hints, \&bind and return;

  say STDERR $socket;
  say STDERR "IS ref? ", ref $hints;
  my $on_listen=$hints->{data}{on_listen}//=\&accept; # Default is to call accept immediately
  my $on_error=$hints->{data}{on_error};

  if(defined IO::FD::DWIM::listen($socket, $hints->{backlog}//1024)){
    say STDERR "Listen ok";
    $on_listen and asap $on_listen , $socket, $hints;
  }
  else {
    $on_error and asap $on_error, $socket, $!;
  }

}

sub accept($$){
  my ($socket, $hints)=@_;

  say STDERR "Accept called";
  say STDERR Dumper $hints;
  _create_socket $socket, $hints, \&bind and return;

  use uSAC::IO::Acceptor;
  my $a;
  $a=uSAC::IO::Acceptor->create(
    fh=>$socket, 
    on_accept=>sub {
      $hints->{acceptor}=$a;    #Add reference to prevent destruction
      say STDERR "INTERNAL CALLBACK FOR ACCEPT";
      # Call the on_accept with new fds ref, peers, ref, listening fd and listening hints
      $hints->{data}{on_accept}->(@_, $hints);
    },
    on_error=> $hints->{data}{on_error}
  );
  $a->start;
  
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


