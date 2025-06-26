package uSAC::IO;
use strict;
use warnings;

no warnings "experimental";

use feature "current_sub";

our $VERSION="v0.1.0";

use constant::more DEBUG=>0;

#Datagram
use constant::more qw<r_CIPO=0 w_CIPO r_COPI w_COPI r_CEPI w_CEPI>;
use Import::These qw<uSAC::IO:: DReader DWriter SWriter SReader>;

use Socket::More;
use Import::These qw<Socket::More:: Constants Interface>;
use constant::more  IPV4_ANY=>"0.0.0.0",
                    IPV6_ANY=>"::";


use Socket::More::Resolver {}, undef;
use IO::FD::DWIM ();
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK :mode);

use Data::Cmp qw<cmp_data>;


sub Dumper;

BEGIN {
  if(DEBUG){
    require Data::Dumper;
    Data::Dumper->import;
  }
}

our $STDIN;
our $STDOUT;
our $STDERR;

use Export::These qw{accept asap timer delay interval timer_cancel sub_process sub_process_cancel connect connect_cancel connect_addr bind pipe pair listen 
dreader dwriter reader writer sreader swriter signal socket_stage asay aprint adump $STDOUT $STDIN $STDERR};

#use Export::These '$STDOUT','$STDIN', '$STDERR';

sub _reexport {
  #eval 'require uSAC::FastPack::Broker;
  #uSAC::FastPack::Broker->import;
  #';
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
sub asap(*@);   # Schedule sub as soon as async possible

# Must return an integer key for the timer.
sub timer ($$$);  # Setup a timer

sub signal ($$);  #Assign a signal handler to a signal

sub child ($$);
sub cancel ($);

# Must delete the timer from store
# Must use alias of argument to make undef
sub timer_cancel ($);
sub connect_cancel ($);
sub connect_addr;
sub _pre_loop;
sub _post_loop;
sub _shutdown_loop;
sub _post_fork;
sub asay;

*asap=\&{$rb."::asap"};                         # Schedual code to run as soon as possible (next tick)
*signal=\&{$rb."::signal"};                         # Schedual code to run as soon as possible (next tick)
*signal_cancel=\&{$rb."::signal_cancel"};                         # Schedual code to run as soon as possible (next tick)
*child=\&{$rb."::child"};                         # Schedual code to run as soon as possible (next tick)
*child_cancel=\&{$rb."::child_cancel"};                         # Schedual code to run as soon as possible (next tick)
*timer=\&{$rb."::timer"};                       # Create a timer, with offset, and repeat, returns ref
*timer_cancel=\&{$rb."::timer_cancel"};         # cancel a timer
*connect_cancel=\&{$rb."::connect_cancel"};     # Cancel a connect
*connect_addr=\&{$rb."::connect_addr"};         # Connect via address structure

*cancel=\&{$rb."::cancel"};

*CORE::GLOBAL::exit=\&{$rb."::_exit"};          # Make global exit shutdown the loop 


*_pre_loop=\&{$rb."::_pre_loop"};               # Internal
*_post_loop=\&{$rb."::_post_loop"};             # Internal
*_shutdown_loop=\&{$rb."::_shutdown_loop"};     # Internal
*_post_fork=\&{$rb."::_post_fork"};     # Internal


#sub _tick_timer;
#*_tick_timer=\&{$rb."::_tick_timer"};                       # Create a timer, with offset, and repeat, returns ref
# Start a 1 second tick timer. This simply updates the 'clock' used for simple
# timeout measurements.


use strict "refs";




# Create a socket from hints and call the indicated callback ( or override when done)
# 
sub _create_socket {
  # Hints are in first argument
  my ($socket, $hints, $override)=@_;
  return undef if defined $socket;

  DEBUG and asay "_create_socket called";
  for($hints){
    my $on_error=$_->{data}{on_error};
    my $on_socket=$override//$_->{data}{on_socket};

    if(defined IO::FD::socket $socket, $_->{family}, $_->{socktype}, $_->{protocol}//0){
      # set socket to non block mode as we are async library ;)
      # TODO open a socket with platform specific flags to avoid this extra call
      my $res= IO::FD::fcntl $socket, F_SETFL, O_NONBLOCK;
      unless (defined $res){
        DEBUG and asay "ERROR in fcntl";
        $on_error && asap $on_error, $socket, $!;
        return;
      }
      DEBUG and asay "ON socket", $on_socket;
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

# Create sockets based on specs provided
# Can be a single spec (hash ) or an array ref or specs
# Or a test needing to be parsed
#
# Also optionall can override the default on_spec callback stored (or not)
# in the resulting spec
#
sub socket_stage($$){
  my ($spec, $next)=@_;
  my @specs;
  if(!ref $spec){
    # Assume string which needs parsing
    push @specs, parse_passive_spec $spec;
  }
  elsif(ref($spec) eq "ARRAY") {
      # array of hash specs
      for(@$spec){
        my $copy;
        %$copy=%$_;
        push @specs, $copy;
      }
  }
  else {
    # Hash spec
    # copy
    my $copy;
    %$copy=%$spec;
    push @specs, $copy;

  }

  #TODO merge spec with merge items
  
  # Override an undefined on_spec function to create a socket
  my $on_spec=$specs[0]{data}{on_spec}//sub { 
    _create_socket undef, $_[1], $next if $_[1];
  };

  DEBUG and asay "about to prepare specs";
  _prep_spec($_, $on_spec) for @specs;
  DEBUG and asay "after to prepare specs";

  1;

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

  DEBUG and asay "BIND CALLED";
  my ($socket, $hints)=@_;

  _create_socket $socket, $hints, __SUB__  and return;

  my $fam;
  my $type;
  my $protocol;
  
  my $addr;

  my $on_bind=$hints->{data}{on_bind};
  my $on_error=$hints->{data}{on_error};
  DEBUG and asay "SOcket is: $socket";
  $type=$hints->{socktype}//=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
  $fam=$hints->{family}//=sockaddr_family IO::FD::DWIM::getsockname $socket;

  for ($hints){
    my %copy=%$_; # Copy the spec?
    my $addr=$copy{addr};

	  IO::FD::setsockopt($socket, SOL_SOCKET, SO_REUSEADDR, pack "i", 1) if $copy{data}{reuse_addr};
		IO::FD::setsockopt($socket, SOL_SOCKET, SO_REUSEPORT, pack "i", 1) if $copy{data}{reuse_port};

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
      DEBUG and asay "Call on_bind", $on_bind;
      $on_bind and $on_bind->($socket, \%copy);
    }
    else {
      DEBUG and asay "ERROR: ". $!;
      my $err=$!;
       $on_error and $on_error->($socket, $err);
    }
  }


}



# TODO: allow a string as a spec to be used instead of hints? Only valid when host is undef.
# TODO: allow host and port (addr and po ) in spec when host and port are undef for spec processing
sub connect ($$){
  DEBUG and asay "Connect called";
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

  DEBUG and asay "CONNECT before";
  _create_socket $socket, $hints, __SUB__ and return;
  DEBUG and asay "CONNECT after";

  # If the type and  family hasn't been specified with hints, extract from socket info
  $type=$hints->{socktype}//=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
  $fam=$hints->{family}//=sockaddr_family IO::FD::DWIM::getsockname $socket;

	if($fam==AF_INET or $fam==AF_INET6){
		#Convert to address structures. DO NOT do a name lookup
		$ok=Socket::More::Resolver::getaddrinfo(
			$host,
			$port,
      $hints,
      sub {
        DEBUG and asay "LOOKUP callback"; 
        my @addresses=@_;
        $addr=$addresses[0]{addr};
	      connect_addr($socket, $addr, $on_connect, $on_error);
        DEBUG and asay time;
      },

      sub{
        DEBUG and asay "LOOKUP ERROR"; 
        DEBUG and asay Dumper $hints;
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
  DEBUG and asay "Listen called";
  my ($socket, $hints)=@_;

  _create_socket $socket, $hints, \&bind and return;

  DEBUG and asay $socket;
  DEBUG and asay "IS ref? ", ref $hints;
  my $on_listen=$hints->{data}{on_listen}//=\&accept; # Default is to call accept immediately
  my $on_error=$hints->{data}{on_error};

  if(defined IO::FD::DWIM::listen($socket, $hints->{backlog}//1024)){
    DEBUG and asay "Listen ok";
    $on_listen and asap $on_listen , $socket, $hints;
  }
  else {
    $on_error and asap $on_error, $socket, $!;
  }

}

sub accept($$){
  my ($socket, $hints)=@_;

  DEBUG and asay "Accept called";
  DEBUG and asay Dumper $hints;
  _create_socket $socket, $hints, \&bind and return;

  use uSAC::IO::Acceptor;
  my $a;
  $a=uSAC::IO::Acceptor->create(
    fh=>$socket, 
    on_accept=>sub {
      $hints->{acceptor}=$a;    #Add reference to prevent destruction
      DEBUG and asay "INTERNAL CALLBACK FOR ACCEPT";
      # Call the on_accept with new fds ref, peers, ref, listening fd and listening hints
      $hints->{data}{on_accept}->(@_, $hints);
    },
    on_error=> $hints->{data}{on_error}
  );
  $a->start;
  
}



# Asynchronous version of  sockaddr_passive
#
sub _prep_spec{
	require Scalar::Util;
	my ($spec, $on_spec)=@_;

  DEBUG and asay "_prep_spec_call";
  DEBUG and asay Dumper $spec;

  $on_spec//=$spec->{data}{on_spec};
  my $on_error=$spec->{data}{on_error};

  # v0.5.2 Copy the input specs
  my %copy=%$spec;
  $spec=\%copy;

  ## Filter
	my @seen;


	my $r={};

	#If no interface provided assume all
	$r->{interface}=$spec->{interface}//".*";
	
  
	$r->{socktype}=$spec->{socktype}//[SOCK_STREAM, SOCK_DGRAM];
	$r->{protocol}=$spec->{protocol}//0;

	#If no family provided assume all
	$r->{family}=$spec->{family}//[AF_INET, AF_INET6, AF_UNIX];	
	
	#Configure port and path
	$r->{port}=$spec->{port}//[];
	$r->{path}=$spec->{path}//[];
	
  
  # Convert to arrays for unified interface 
  for($r->{socktype}, $r->{family}){
    unless(ref eq "ARRAY"){
      $_=[$_];
    }
  }

  for($r->{socktype}->@*){
    unless(Scalar::Util::looks_like_number $_){
      ($_)=string_to_socktype $_;
    }
  }

  for($r->{family}->@*){
    unless(Scalar::Util::looks_like_number $_){
      ($_)=string_to_family $_;
    }
  }
  # End
  #####


	#NOTE: Need to add an undef value to port and path arrays. Port and path are
	#mutually exclusive
	if(ref($r->{port}) eq "ARRAY"){
		unshift $r->{port}->@*, undef;
	}
	else {
		$r->{port}=[undef, $r->{port}];
	}


	if(ref($r->{path}) eq "ARRAY"){
		unshift $r->{path}->@*, undef;
	}
	else {
		$r->{path}=[undef, $r->{path}];
	}

	die "No port number specified, no address information will be returned" if ($r->{port}->@*==0) or ($r->{path}->@*==0);

	#Delete from combination specification... no need to make more combos
  #
  my $enable_group=exists $spec->{group};

	my $address=delete $spec->{address};
	my $group=delete $spec->{group};
	my $data=delete $spec->{data};
  my $flags=(delete $spec->{flags})//0;

	$address//=".*";
	$group//=".*";

	#Ensure we have an array for later on
	if(ref($address) ne "ARRAY"){
		$address=[$address];
	}

	if(ref($group) ne "ARRAY"){
		$group=[$group];
	}

	my @interfaces=(Socket::More::make_unix_interface, Socket::More::getifaddrs);

	#Check for special cases here and adjust accordingly
	my @new_address;
	my @new_interfaces;
	##my @new_spec_int;
	my @new_fam;

  # IF IPV4_ANY or IPV6_ANY is specified,  nuke any other address provided
  #
	if(grep /${\IPV4_ANY()}/, @$address){
		#push @new_spec_int, IPV4_ANY;
		push @new_address, IPV4_ANY;
		push @new_fam, AF_INET;
    my @results;
    Socket::More::Lookup::getaddrinfo(
      IPV4_ANY,
      "0",
      {flags=>AI_NUMERICHOST|AI_NUMERICSERV, family=>AF_INET},
      @results
    );


		push @new_interfaces, ({name=>IPV4_ANY,addr=>$results[0]{addr}});
	}

	if(grep /${\IPV6_ANY()}/, @$address){
		#push @new_spec_int, IPV6_ANY;
		push @new_address, IPV6_ANY;
    push @new_fam, AF_INET6;
    my @results;
    Socket::More::Lookup::getaddrinfo(
      IPV6_ANY,
      "0",
      {flags=>AI_NUMERICHOST|AI_NUMERICSERV, family=>AF_INET6},
      @results
    );

    push @new_interfaces, ({name=>IPV6_ANY, addr=>$results[0]{addr}});
	}


  # TODO: Also add special case for multicast interfaces? for datagrams?

	if(@new_address){
		@$address=@new_address;
		@interfaces=@new_interfaces;
		$r->{interface}=[".*"];
	}

	#$r->{family}=[@new_fam];

	#Handle localhost
	if(grep /localhost/, @$address){
		@$address=('127.0.0.1');#,'::1');
		$r->{interface}=[".*"];
	}

  

  $r->{address}=$address;

  DEBUG and asay Dumper $r;
	#Generate combinations
	my $result=Data::Combination::combinations $r;
	
  DEBUG and asay Dumper $result;

	#Retrieve the interfaces from the os
	#@interfaces=(make_unix_interface, Socket::More::getifaddrs);


	#Poor man dereferencing
	my @results=$result->@*;
	
	#Force preselection of matching interfaces
	@interfaces=grep {
		my $interface=$_;
		scalar grep {$interface->{name} =~ $_->{interface}} @results
	} @interfaces;

	#Validate Family and fill out port and path
  no warnings "uninitialized";

	my @output;

  #Total number of probable combinations
  my $count=@interfaces*@results;
  my $at_least_1=0;
	for my $interface (@interfaces){
    DEBUG and asay "======INTERFACE ".Dumper $interface;
		my $fam= sockaddr_family($interface->{addr});
    DEBUG and asay "family is $fam";
		for(@results){

      DEBUG and asay "Result family", Dumper $_;
			next if $fam != $_->{family};

			#Filter out any families which are not what we asked for straight up

			goto CLONE if ($fam == AF_UNIX) 
				&& ($interface->{name} eq "unix")
				#&& ("unix"=~ $_->{interface})
				&& (defined($_->{path}))
				&& (!defined($_->{port}));


			goto CLONE if
				($fam == AF_INET or $fam ==AF_INET6)
				&& defined($_->{port})
				&& !defined($_->{path})
				&& ($_->{interface} ne "unix");

			next;

	CLONE:
      # Used to see if a spec matched at all before async lookup
      $at_least_1++;
			my %clone=$_->%*;			
			my $clone=\%clone;
			$clone{data}=$spec->{data};
      $clone{flags}=$spec->{flags};

			#A this point we have a valid family  and port/path combo
			#
			my ($err, $res, $service);

      # Complete the clone interface info
      $clone->{interface}=$interface->{name};
      $clone->{if}=$interface;  # From v0.5.0

			#copy data to clone
			$clone->{data}=$data;
      $clone->{flags}=$flags;


      DEBUG and asay Dumper $clone;
      if($fam == AF_UNIX){
        # Assume no lookup is needed for this
        my $suffix=$_->{socktype}==SOCK_STREAM?"_S":"_D";
				$clone->{addr}=pack_sockaddr_un $_->{path}.$suffix;
				my $path=unpack_sockaddr_un($clone->{addr});			
				$clone->{address}=$path;
				$clone->{path}=$path;
				$clone->{interface}=$interface->{name};
				$clone->{group}="UNIX" if $enable_group;

      }

      elsif(!exists $_->{address} or $_->{address} eq ".*"){
        # No address to look up, assuming the binary addr field is set
        #
        DEBUG and asay "address does not exist or is wild $_->{address}";
        DEBUG and asay  "Address needs to be filled";
        if($fam == AF_INET){
          DEBUG and asay "DOING IPv4";
          my (undef, $ip)=unpack_sockaddr_in($interface->{addr});
          Socket::More::Lookup::getnameinfo($interface->{addr}, my $host="", my $port="", NI_NUMERICHOST|NI_NUMERICSERV);

          $clone->{address}=$host;
          $clone->{addr}=pack_sockaddr_in($_->{port}, $ip);
          if($enable_group){
            require Socket::More::IPRanges;
            $clone->{group}=Socket::More::IPRanges::ipv4_group($clone->{address});
          }
        }

        elsif($fam == AF_INET6){
          DEBUG and asay "DOING IPv6";
          my(undef, $ip, $scope, $flow_info)=unpack_sockaddr_in6($interface->{addr});
          Socket::More::Lookup::getnameinfo($interface->{addr}, my $host="", my $port="", NI_NUMERICHOST|NI_NUMERICSERV);
          $clone->{address}=$host;
          $clone->{addr}=pack_sockaddr_in6($_->{port},$ip, $scope, $flow_info);
          if($enable_group){
            require Socket::More::IPRanges;
            $clone->{group}=Socket::More::IPRanges::ipv6_group($clone->{address});
          }
        }
        else {
          # Unsupported AF
        }

        # break synchronous callback
        next unless grep {$clone->{address}=~ /$_/i } @$address;
        if($enable_group){
          next  unless grep {$clone->{group}=~ /$_/i } @$group;
        }
        next unless defined $clone->{addr};
        
        
        #send out for async
        my $found;
        for(my $i=0; $i<@seen; $i++){
          my $s=$seen[$i];
          $found=grep {!cmp_data($clone, $s)} @seen; 
          last if $found;
        }

        if(!$found){
          push @seen, $clone;
          asay "calling on spec for $clone";
          $on_spec and asap $on_spec, undef, $clone;
        }
      }

      else {
        # Address exists so we (potentially need to) lookup to generate binary addr field
        #
          my @results;
          Socket::More::Lookup::getaddrinfo($_->{address},$_->{port},$_, @results);
          $clone->{addr}=$results[0]{addr};
          DEBUG and asay "RESULTS ", Dumper @results;
          DEBUG and asay "spec ", Dumper $_;

          Socket::More::Resolver::getaddrinfo($_->{address},$_->{port},$_, 
            sub {
              # NOTE ONLY USES THE FIRST RESULT
              $clone->{addr}=$_[0]{addr};
              return unless grep {$clone->{address}=~ /$_/i } @$address;
              if($enable_group){
                return unless grep {$clone->{group}=~ /$_/i } @$group;
              }
              return unless defined $clone->{addr};
              
              #send out for async
              my $found;
              for(my $i=0; $i<@seen; $i++){
                my $s=$seen[$i];
                my $found=grep {!cmp_data($clone, $s)} @seen; 
                last if $found;
              }

              if(!$found){
                push @seen, $clone;
                asay "calling on spec for  existing addresss $clone";
                $on_spec and $on_spec->(undef, $clone);
              }

            },

            sub {
             DEBUG and asay "getaddrinfo error", "@_", gai_strerror($_[0]);
            $on_error->()    # Use on error
          }
          );
      }
    }
  }

  # Call error callback if the specification don't actuall match anything
  $on_error and asap $on_error, undef, "No results" unless $at_least_1;

  # Send end message
  #$on_spec and asap $on_spec, undef, undef;

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
    #DEBUG and asay "OTHER SOCKET TYPE";
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
		$r->pipe_to($w);
		return ($r,$w);	
	}
	();
}

sub delay {
  
  my ($d,$cb)=@_;
  timer $d, 0, $cb;
}

sub interval {
  my ($int,$cb)=@_;
  timer 0, $int, $cb;
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

my %procs;
# Internal for and of fork/exec
# Creates pipes for communicating to child processes
sub sub_process ($;$$$$){
  my ($cmd, $on_complete)=@_;

  my @pipes;
  # Create pipes?
  IO::FD::pipe $pipes[r_CIPO], $pipes[w_CIPO];    # Create pipe for input to child
  IO::FD::pipe $pipes[r_COPI], $pipes[w_COPI];    # Create pipe for input to parent
  IO::FD::pipe $pipes[r_CEPI], $pipes[w_CEPI];    # Create pipe for input to parent

  # Fork and then exec? . Or do we use a template process
  my $pid=fork;
  if($pid){
    # parent
    # Close the ends of the pipe not needed
    IO::FD::close $pipes[r_CIPO];
    IO::FD::close $pipes[w_COPI];
    IO::FD::close $pipes[w_CEPI];

    # store for later refernce
    #
    #

    my $writer=uSAC::IO::writer $pipes[w_CIPO];
    my $reader=uSAC::IO::reader $pipes[r_COPI];
    my $error=uSAC::IO::reader $pipes[r_CEPI];
    


    my $c={pid=>$pid, pipes=>\@pipes, reader=>$reader, error=>$error, writer=>$writer};
    $procs{$pid}=$c;
    #asay "created child $pid";
    uSAC::IO::child $pid, sub {
      my ($ppid, $status)=@_;

        if($procs{$ppid}){
          $procs{$ppid}{pid}=0; # Mark as done
        }

        #my $dc=delete $procs{$ppid}; 
        # Close pipes
        #IO::FD::close $pipes[w_CIPO];
        #IO::FD::close $pipes[r_COPI];
        #IO::FD::close $pipes[r_CEPI];
        
        # remove the watchers
        #$reader->pause;
        #$error->pause;
        $on_complete and  $on_complete->($status, $ppid); #Status first to match perl system command
        #asay "AFTER WHILE $ppid";
    };

    return ($writer, $reader, $error, $pid);
  }
  else {
    # child
    # Close parent ends
    IO::FD::close $pipes[w_CIPO];
    IO::FD::close $pipes[r_COPI];
    IO::FD::close $pipes[r_CEPI];
    
    # Duplicate the fds to stdin, stdout and stderr
    IO::FD::dup2 $pipes[r_CIPO], 0;  
    IO::FD::dup2 $pipes[w_COPI], 1;  
    IO::FD::dup2 $pipes[w_CEPI], 2;  

    # Close originals
    IO::FD::close $pipes[r_CIPO];
    IO::FD::close $pipes[w_COPI];
    IO::FD::close $pipes[w_CEPI];

    # Restart and ASAP timer, and other even clean up
    #
    _post_fork;
    # Do it!
    if($cmd){
      exec $cmd or asay $STDERR, $! and exit;
    }


  }

}

# Kill a job if it isn't already finished
sub sub_process_cancel($){
    my $dc=delete $procs{$_[0]}; 
    if($dc){
        my $pid=$dc->{pid};
         # Only kill the process if its still running

        if($pid){
          DEBUG and asay $STDERR, "Killing sub process $pid";
          kill "KILL", $pid 
        }
        else{
          DEBUG and asay $STDERR, "Sub process $pid already complete";
        }

        # close the fds!
        IO::FD::close $dc->{pipes}[w_CIPO];
        IO::FD::close $dc->{pipes}[r_COPI];
        IO::FD::close $dc->{pipes}[r_CEPI];
        $dc->{reader}=undef;
        $dc->{error}=undef;
        $dc->{writer}=undef;
        $_[0]=undef;
    }
}

#synchronous
sub _map :prototype($){
  my $filter=shift;
  sub {
    my ($next, $index, @options)=@_;
    sub {
      #my $cb=$_[$#_];
      @{$_[0]}= map $filter->($_), @{$_[0]};
      &$next;
    }
  }
}

#synchronous
sub _grep :prototype($){
  my $filter=$_[0];
  sub {
    my ($next, $index, @options)=@_;
    sub {
      @{$_[0]}= grep $_=~ $filter, @{$_[0]};
      &$next;
    }
  }
}

#synchronous
sub _upper :prototype(){
  sub {
    my ($next, $index, @options)=@_;
    sub {
      for my($s)(@{$_[0]}){
        $s=uc $s; 
      }
      &$next;
    }
  }
}

sub _lower :prototype(){
  sub {
    my ($next, $index, @options)=@_;
    sub {
      for my($s)(@{$_[0]}){
        $s=lc $s; 
      }
      &$next;
    }
  }
}

#synchronous
sub _lines {
  my $sep=$/; # save input seperator
  my $buffer=""; # buffing
  sub {
    my ($next, $index, @options)=@_;
    sub {

      # expects last element as a callback, if  no callback is last data
      my $cb=pop;

      # Alias of in put means consumed in place 
      #
      my @lines;
      push @lines, split $sep, $_ for @{$_[0]};

      #If the buffer does not end in a line
      # and we have callback, we expect more data
      if($cb and $_[0]!~/$sep$/){
        # Set buffer to partial line
        $_[0]=pop @lines;
      }
      $next->(\@lines, $cb);
    }
  }
}


# return accumulated results from stdout
#
sub _accumulate {
  my $buffer="";
  sub {
    my ($next, $index, @options)=@_;
    sub {
      my $cb=pop;
      $buffer .= $_ for @{$_[0]};

      # Call next with no callback provided. Marks end or data
      $next->([$buffer], $cb) unless $cb;
    }
  }
}


use Sub::Middler;

sub _backtick {
  my $cmd=shift;
  my $on_result=shift;


  my $buffer="";
  my $status;
  my $pid;
  my @io;

  ($pid, @io)= sub_process $cmd, sub {
      ($status, $pid)=@_;
      $on_result and $on_result->([$buffer, $status, $pid], undef);
  };

  # Back tick handles stadard out only
  $io[1]->on_read=sub {
    $buffer.=$_[0]; $_[0]="";
  };

  # Consume the error stream
  $io[2]->on_read=sub {
    $_[0]="";
  };

  # Start readers
  $io[1]->start;
  $io[2]->start;

}


# Run another command, linking stdio
#
sub system ($;$$$$){

}

# Fork this process. setup broker/node for communications via pipes
# 
sub worker {
  #sub_process;
}


my $dummy=sub{};

sub asay {
  use feature "isa";
  my $w=$STDOUT; # Use the std out if
  my $cb=$dummy;
  if($_[0] isa "uSAC::IO::Writer"){
    $w=shift @_;
  } 
  
  if(ref $_[$#_] eq "CODE"){
    $cb=pop @_;
  }

  $w->write([join("", @_, "\n")], $cb);
  ();
}

sub aprint {
  use feature "isa";
  my $w=$STDOUT; # Use the std out if
  my $cb=$dummy;
  if($_[0] isa "uSAC::IO::Writer"){
    $w=shift @_;
  } 
  
  if(ref $_[$#_] eq "CODE"){
    $cb=pop @_;
  }

  $w->write([join("", @_, "")], $cb);
  ();
}

sub adump {
  use feature "isa";
  my $w=$STDOUT; # Use the std out if
  my $cb=$dummy;
  if($_[0] isa "uSAC::IO::Writer"){
    $w=shift @_;
  } 
  
  if(ref $_[$#_] eq "CODE"){
    $cb=pop @_;
  }

  $w->write([Dumper @_], $cb);
  ();

}




1;
