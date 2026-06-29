package uSAC::IO;
use v5.36;

no feature "signatures";
no warnings "experimental";
use feature "current_sub";

our $VERSION="v0.1.0";


# This is an explicit check to see if usac has been invoked
#
unless($uSAC::Loaded::Loaded){
  #print STDERR "Script must be loaded by usac ( not perl directly)" ;
  #exit;
}

# Test to see if actually loaded via usac

use IO::FD;
use IO::FD::DWIM;
use File::Path qw<make_path remove_tree>;

use Data::Dumper;
use Data::FastPack::Meta;
use Data::Combination;
use constant::more DEBUG=>0;

#Datagram
use constant::more qw<r_CIPO=0 w_CIPO r_COPI w_COPI r_CEPI w_CEPI>;
#use Import::These qw<uSAC::IO:: DReader DWriter SWriter SReader>;

require Socket::More;
require Socket::More::Lookup;

use Import::These qw<Socket::More:: Constants Interface>;
use constant::more  IPV4_ANY=>"0.0.0.0",
                    IPV6_ANY=>"::";


use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK :mode);

use Data::Cmp qw<cmp_data>;


our $STDIN;
our $STDOUT;
our $STDERR;

use Export::These qw{accept asap timer delay interval timer_cancel sub_process sub_process_cancel backtick getaddrinfo getnameinfo connect connect_cancel connect_addr bind pipe pair listen 
dreader dwriter reader writer sreader swriter signal socket_stage asay asay_now aprint aprint_now adump adump_now $STDOUT $STDIN $STDERR
io_lines io_accumulate io_grep io_filter io_upper io_lower
io_file_open
io_file_slurp
io_file_spurt
path_create
path_remove
create_socket
};

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
no warnings "redefine";

our $Clock=time;


# Must return 1
# Takes a sub as first argument, remaining arguments are passed to sub
sub atry :prototype($$;@);   # Schedule sub as soon as async possible

# Must return an integer key for the timer.
sub timer  :prototype($$$);  # Setup a timer

sub signal  :prototype($$);  #Assign a signal handler to a signal

sub child  :prototype($$);
sub cancel  :prototype($);

# Must delete the timer from store
# Must use alias of argument to make undef
sub timer_cancel  :prototype($);
sub connect_cancel  :prototype($);
sub connect_addr;
sub _pre_loop;
sub _post_loop;
sub _shutdown_loop;
sub _post_fork;
sub asay;
sub asay_now;
sub adump;
sub adump_now;

*atry=\&{$rb."::atry"};                         # Schedual code to run as soon as possible (next tick)
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
*exit=\&{$rb."::_exit"};          # Make global exit shutdown the loop 


*_pre_loop=\&{$rb."::_pre_loop"};               # Internal
*_post_loop=\&{$rb."::_post_loop"};             # Internal
*_shutdown_loop=\&{$rb."::_shutdown_loop"};     # Internal
*_post_fork=\&{$rb."::_post_fork"};     # Internal


#sub _tick_timer;
#*_tick_timer=\&{$rb."::_tick_timer"};                       # Create a timer, with offset, and repeat, returns ref
# Start a 1 second tick timer. This simply updates the 'clock' used for simple
# timeout measurements.


use strict "refs";

sub asap {
  my $code=shift;
  unshift @_, undef;
  unshift @_, $code;
  &atry;
}


# Create a socket from hints and call the indicated callback ( or override when done)
# 
sub create_socket{
  # Hints are in first argument
  my ($socket, $hints, $override)=@_;
  return undef if defined $socket;

  DEBUG and adump $STDERR, "create_socket called", $hints;
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
      DEBUG and asay $STDERR, "ON socket ".$on_socket;
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
sub socket_stage :prototype($;$){
  my ($spec, $next)=@_;
  my @specs;
  if(!ref $spec){
    # Assume string which needs parsing
    push @specs, Socket::More::parse_passive_spec($spec);
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
    DEBUG and asay $STDERR, "on spec called---";
    create_socket undef, $_[1], $next if $_[1];
  };

  DEBUG and asay $STDERR, "about to prepare specs";
  _prep_spec($_, $on_spec) for @specs;
  DEBUG and asay $STDERR, "after to prepare specs";

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
sub bind  :prototype($$) {

  my ($socket, $hints)=@_;
  DEBUG and adump $STDERR, "$$ BIND CALLED: ", $socket, $hints;
  #DEBUG and asay $STDERR, "$$ ". Dumper $socket, $hints;

  create_socket $socket, $hints, __SUB__  and return;

  my $fam;
  my $type;
  my $protocol;
  
  my $addr;

  my $on_bind=$hints->{data}{on_bind};
  my $on_error=$hints->{data}{on_error};
  DEBUG and asay $STDERR, "SOcket is: $socket";
  $type=$hints->{socktype}//=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
  $fam=$hints->{family}//=Socket::More::sockaddr_family( IO::FD::DWIM::getsockname $socket);

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
      DEBUG and asay $STDERR, "Call on_bind " .$on_bind;
      #DEBUG and asay $STDERR, Dumper $socket, \%copy;
      $on_bind and $on_bind->($socket, \%copy);
    }
    else {
      DEBUG and asay $STDERR, "ERROR: ". $!;
      my $err=$!;
       $on_error and $on_error->($socket, $err);
    }
  }


}



# TODO: allow a string as a spec to be used instead of hints? Only valid when host is undef.
# TODO: allow host and port (addr and po ) in spec when host and port are undef for spec processing
sub connect  :prototype($$){
  DEBUG and asay $STDERR, "Connect called";
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

  DEBUG and asay $STDERR, "CONNECT before";
  create_socket $socket, $hints, __SUB__ and return;
  DEBUG and asay $STDERR, "CONNECT after";

  # If the type and  family hasn't been specified with hints, extract from socket info
  $type=$hints->{socktype}//=unpack "I", IO::FD::DWIM::getsockopt $socket, SOL_SOCKET, SO_TYPE;
  $fam=$hints->{family}//=Socket::More::sockaddr_family(IO::FD::DWIM::getsockname $socket);

	if($fam==AF_INET or $fam==AF_INET6){
    DEBUG and asay $STDERR, "===connect AF INET/6";
		#Convert to address structures. DO NOT do a name lookup
    #$ok=Socket::More::Resolver::getaddrinfo(
		$ok=uSAC::IO::getaddrinfo(
			$host,
			$port,
      $hints,
      sub {
        #DEBUG and asay $STDERR, "$$ LOOKUP callback ". Dumper (@_); 
        my @addresses=@_;

        unless(@addresses){
          $on_error and $on_error->($socket, "Host $hints->{address} could not be found");
          return;
        }

        $addr=$addresses[0]{addr};
        #DEBUG and asay $STDERR, "$$ socket: $socket, addr ". Dumper($addr); 
	      connect_addr($socket, $addr, $on_connect, $on_error);
        DEBUG and asay $STDERR, time;
      },

      sub{
        DEBUG and asay $STDERR, "$$ LOOKUP ERROR"; 
        #DEBUG and asay $STDERR, Dumper $hints;
        $on_error and $on_error->($socket, Socket::More::Lookup::gai_strerror($!));
      }
		);
	}
	elsif($fam==AF_UNIX){
    DEBUG and asay $STDERR, "===connect AF UNIX";
		$addr=Socket::More::pack_sockaddr_un($host);
	  connect_addr($socket, $addr, $on_connect, $on_error);
	}
	else {
    #die "Unsupported socket address family";
    $on_error and asap $on_error, $socket, "Unsupported socket address family";
	}
}

sub listen ($$) {
  my ($socket, $hints)=@_;

  create_socket $socket, $hints, \&bind and return;

  DEBUG and asay $STDERR, $socket;
  DEBUG and asay $STDERR, "IS ref? ", ref $hints;
  my $on_listen=$hints->{data}{on_listen}//=\&accept; # Default is to call accept immediately
  my $on_error=$hints->{data}{on_error};

  if(defined IO::FD::DWIM::listen($socket, $hints->{backlog}//1024)){
    DEBUG and asay $STDERR, "Listen ok";
    $on_listen and asap $on_listen , $socket, $hints;
  }
  else {
    $on_error and asap $on_error, $socket, $!;
  }

}

sub accept :prototype($$) {
  my ($socket, $hints)=@_;

  #DEBUG and asay $STDERR, "Accept called";
  #DEBUG and asay $STDERR, Dumper $hints;
  create_socket $socket, $hints, \&bind and return;

  use uSAC::IO::Acceptor;
  my $a;
  $a=uSAC::IO::Acceptor->create(
    fh=>$socket, 
    on_accept=>sub {
      $hints->{acceptor}=$a;    #Add reference to prevent destruction
      DEBUG and asay $STDERR, "INTERNAL CALLBACK FOR ACCEPT";
      # Call the on_accept with new fds ref, peers, ref, listening fd and listening hints
      $hints->{data}{on_accept}->(@_, $hints);
    },
    on_error=> $hints->{data}{on_error}
  );
  $a->start;
  $a;
  
}



# Asynchronous version of  sockaddr_passive
#
sub _prep_spec{
	require Scalar::Util;
	my ($spec, $on_spec)=@_;

  #DEBUG and asay $STDERR, "_prep_spec_call";
  #DEBUG and asay $STDERR, Dumper $spec;

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
      ($_)=Socket::More::string_to_socktype($_);
    }
  }

  for($r->{family}->@*){
    unless(Scalar::Util::looks_like_number $_){
      ($_)=Socket::More::string_to_family($_);
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

	my @interfaces=(Socket::More::make_unix_interface(), Socket::More::getifaddrs());

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
      \@results
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
      \@results
    );

    push @new_interfaces, ({name=>IPV6_ANY, addr=>$results[0]{addr}});
	}


  # TODO: Also add special case for multicast interfaces? for datagrams?

	if(@new_address){
		@$address=@new_address;
		@interfaces=@new_interfaces;
		$r->{interface}//=[".*"];
	}

	#$r->{family}=[@new_fam];

	#Handle localhost
	if(grep /localhost/, @$address){
		@$address=('127.0.0.1');#,'::1');
		$r->{interface}//=[".*"];
	}

  

  $r->{address}=$address;
  #DEBUG and asay $STDERR, "==== Structure used for combinations======";
  #DEBUG and asay $STDERR, Dumper $r;
	#Generate combinations
	my $result=Data::Combination::combinations $r;
	
  #DEBUG and asay $STDERR, "==== Results combinations======";
  #DEBUG and asay $STDERR, Dumper $result;

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
    #DEBUG and asay $STDERR, "======INTERFACE ".Dumper $interface;
		my $fam= Socket::More::sockaddr_family($interface->{addr});
    DEBUG and asay $STDERR, "family is $fam";
		for(@results){

      #DEBUG and asay $STDERR, "Result family", Dumper $_;
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

      DEBUG and asay $STDERR, "=====SETUP CLONE";
      #DEBUG and asay $STDERR, Dumper $clone;
      if($fam == AF_UNIX){
        # Assume no lookup is needed for this
        my $suffix=$_->{socktype}==SOCK_STREAM?"_S":"_D";
				$clone->{addr}=Socket::More::pack_sockaddr_un($_->{path}.$suffix);
				my $path=Socket::More::unpack_sockaddr_un($clone->{addr});			
				$clone->{address}=$path;
				$clone->{path}=$path;
				$clone->{interface}=$interface->{name};
				$clone->{group}="UNIX" if $enable_group;

      }

      elsif(!exists $_->{address} or $_->{address} eq ".*"){
        # No address to look up, assuming the binary addr field is set
        #
        DEBUG and asay $STDERR, "address does not exist or is wild $_->{address}";
        DEBUG and asay  $STDERR, "Address needs to be filled";
        if($fam == AF_INET){
          DEBUG and asay $STDERR, "DOING IPv4";
          my (undef, $ip)=Socket::More::unpack_sockaddr_in($interface->{addr});
          Socket::More::Lookup::getnameinfo($interface->{addr}, my $host="", my $port="", NI_NUMERICHOST|NI_NUMERICSERV);

          $clone->{address}=$host;
          $clone->{addr}=Socket::More::pack_sockaddr_in($_->{port}, $ip);
          if($enable_group){
            require Socket::More::IPRanges;
            $clone->{group}=Socket::More::IPRanges::ipv4_group($clone->{address});
          }
        }

        elsif($fam == AF_INET6){
          DEBUG and asay $STDERR, "DOING IPv6";
          my(undef, $ip, $scope, $flow_info)=unpack_sockaddr_in6($interface->{addr});
          Socket::More::Lookup::getnameinfo($interface->{addr}, my $host="", my $port="", NI_NUMERICHOST|NI_NUMERICSERV);
          $clone->{address}=$host;
          $clone->{addr}=Socket::More::pack_sockaddr_in6($_->{port},$ip, $scope, $flow_info);
          if($enable_group){
            require Socket::More::IPRanges;
            $clone->{group}=Socket::More::IPRanges::ipv6_group($clone->{address});
          }
        }
        else {
          # Unsupported AF
          DEBUG and asay $STDERR, "====UNSPPORTED AF";
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
          DEBUG and asay $STDERR, "calling on spec for $clone";
          $on_spec and asap $on_spec, undef, $clone;
        }
      }

      else {
        # Address exists so we (potentially need to) lookup to generate binary addr field
        #
          my @results;
          Socket::More::Lookup::getaddrinfo($_->{address},$_->{port},$_, \@results);
          $clone->{addr}=$results[0]{addr};
          #DEBUG and asay $STDERR, "$$ RESULTS ", Dumper @results;
          #DEBUG and asay $STDERR, "$$ spec ", Dumper $_;

          #Socket::More::Resolver::getaddrinfo($_->{address},$_->{port},$_, 
          uSAC::IO::getaddrinfo($_->{address},$_->{port}, $_, 
            sub {
              #DEBUG and asay $STDERR, "++++++$$ GAI CALLBACK++++ ". Dumper @_;

              # NOTE ONLY USES THE FIRST RESULT
              $clone->{addr}=$_[0]{addr};
              #DEBUG and asay $STDERR, "++++++$$ GAI CLONE". Dumper $clone;
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
                DEBUG and asay $STDERR, "calling on spec for  existing addresss $clone";
                $on_spec and $on_spec->(undef, $clone);
              }

            },

            sub {
             DEBUG and asay $STDERR, "getaddrinfo error", "@_";
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
  require uSAC::IO::DReader;
	&uSAC::IO::DReader::create;
}
sub sreader {
  require uSAC::IO::SReader;
	&uSAC::IO::SReader::create;
}

sub dwriter {
  require uSAC::IO::DWriter;
	&uSAC::IO::DWriter::create;
}
sub swriter {
  require uSAC::IO::SWriter;
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

sub pipe ($$){
	my ($rfh,$wfh)=@_;
	my ($r, $w)=(reader($rfh), writer($wfh));
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

our %procs;
# Internal for and of fork/exec
# Creates pipes for communicating to child processes
# First argument is command or code to run
# Second is on_complete
# Thirt is optional on_read handler for stdout
# Forth is optional on_read handerl for stderr
#
# Returns array of (writer, reader, reader, pid)
#
sub sub_process ($;$$$$){
  my ($cmd, $on_parent, $on_complete, $on_stdout, $on_stderr)=@_;
  #asay $STDERR, 'TOP OF sub_Pocess : '. $cmd;

  asap sub {
  my @pipes;
  # Create pipes?
  IO::FD::pipe $pipes[r_CIPO], $pipes[w_CIPO];    # Create pipe for input to child
  IO::FD::pipe $pipes[r_COPI], $pipes[w_COPI];    # Create pipe for input to parent
  IO::FD::pipe $pipes[r_CEPI], $pipes[w_CEPI];    # Create pipe for input to parent

  # Fork and then exec? . Or do we use a template process
  my $pid=fork;
  DEBUG and asay $STDERR, "PID AFTER FORK--- $pid \n";
  if($pid){
    DEBUG and asay $STDERR, "IN PARENT FORK $$";
    use feature "state";
    state $i=0;
    $i++; 

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
    
    $reader->pipe_to($STDOUT);
    $error->pipe_to($STDERR);


      asay_now $STDERR, "$writer $reader $error $pid";
    my $c={pid=>$pid, pipes=>\@pipes, reader=>$reader, error=>$error, writer=>$writer};
    $procs{$pid}=$c;
    DEBUG and asay $STDERR, "created child $pid";

    #_shutdown_loop;
    uSAC::IO::child $pid, sub {
      my ($ppid, $status)=@_;
        if($procs{$ppid}){
          #$procs{$ppid}{pid}=0; # Mark as done
          delete $procs{$ppid};
        }

        local $?=$status;
        asay $STDERR, " Process complete status $?";

        $on_complete and  $on_complete->([$status, $ppid]); #Status first to match perl system command
        #asay $STDERR, "AFTER WHILE $ppid";
    };

      $reader->on_read=$on_stdout if $on_stdout;
      $error->on_read=$on_stderr if $on_stderr;

      #return ($writer, $reader, $error, $pid);
    $on_parent and  $on_parent->($writer, $reader, $error,$pid);

  }
  else {
    # child
    asay_now $STDERR, "-- IN CHILD $$ --";
    my $cpid=$$;
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


    # Shedual the code to reconfigure the run loop

    # Give child opertunity to do extra setup
    #
    #!$pid and $on_fork and asap $on_fork, $pid;


    # Do it!
    # If a cmd if provided exec is called. and this function never returns in
    # the client
    #
    # If NO cmd is provided, the on_fork is actuall the entry point for the
    # child worker. It is schedulled to run from top level and this state or
    # execution is stoped with a die call. This function never returns in the
    # client
    # 
    if(defined $cmd and ! ref $cmd){
      DEBUG and asay $STDERR, "$cpid CMD IS A STRING ======= $cmd";
      exec $cmd or asay $STDERR, $! and exit -1; # TODO... how to fix this... 

      #TODO signal to parent the exec failed somehow??
      
    }
    elsif(defined $cmd) {
      # USE ASAP here to force handling of the special
      # exception to restart the child
      #asap sub {
      $uSAC::Main::worker_sub =$cmd; #, $pid; #Shedual
      DEBUG and asay $STDERR, "$cpid CMD IS A CODE REF======= $cmd";
      # Stop all watchers, and stop the event loop
      die " $cpid RETURN FROM CHILD";
      #};
      #return ();
    }
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
        $dc->{reader}->destroy;;
        $dc->{error}->destroy;
        $dc->{writer}->destroy;

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



# Jobs
# Jobs are sub processes which:
#   Generate data for disk or external placment
#   presents all STDIN, STDOUT and STDERR as fast pack messages for control and status
#   queued (schedualed)
#   persitent 
#   
#   perl process become a 'server' responding to fastpack messages

my @queue;

sub schedual_job  {

  #
}


#synchronous
sub io_map :prototype($){
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

#Inplace
sub io_grep :prototype($){
  my $filter=$_[0];
  sub {
    my ($next)=@_;
    sub {
      @{$_[0]}= grep $_=~ $filter, @{$_[0]};
      &$next;
    }
  }
}

# Inplace
sub io_filter :prototype($){
  my $filter=$_[0];
  sub {
    my ($next)=@_;
    sub {
      @{$_[0]}= grep $_=~ $filter, @{$_[0]};
      &$next;
    }
  }
}

#synchronous
#Modify inputs
sub io_upper :prototype(){
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

sub io_lower :prototype(){
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
#consumes input
sub io_lines {
  my $sep=shift//$/; # save input seperator
  my $slen=length $sep;
  my $buffer=""; # buffing
  sub {
    my ($next, $index, @options)=@_;
    sub {
      my @lines;

      # expects last element as a callback, if  no callback is last data
      my $cb=$_[$#_];

      # Alias of in put means consumed in place 
      #
      my $idx;
      for(@{$_[0]}){
        while(($idx=index $_, $sep)>=0){
          # found sep
          if($buffer){
            push @lines, $buffer.substr $_, 0, $idx, ""; #extract line
            $buffer="";
          }
          else {
            push @lines, substr $_, 0, $idx, ""; #extract line
          }
          substr $_, 0, $slen,""; #//Strip sep
        }
        # accumulate remainder to buffer
        $buffer.=$_;
      }

      if($cb){
        $cb->();
      }
      else{
        # Add the remainder if last call
        push @lines, $buffer;
        $next->(\@lines, $cb);
      }
    }
  }
}


# return accumulated results from stdout
# consumes input
sub io_accumulate {
  my $buffer=[""];
  sub {
    my ($next, $index, @options)=@_;
    sub {
      my $cb=pop;
      # Consume input, but leave array
      $buffer->[0] .= pop $_[0]->@* for @{$_[0]};

      
      # Call next with no callback provided. Marks end or data
      if($cb){
        #Do callback to indicate data is consumed;
        $cb->();
      }
      else {
        # No more data (no cb) so finish it
        $next->($buffer, $cb)
      }
    }
  }
}

# Copy the input argument. Prevents future operations form modifiing input data
# INPUTS are left unchanged
sub io_copy {
  my @buffer;
  sub {
    my ($next, $index, @options)=@_;
    sub {
      my $cb=pop;
      @buffer= $_[0]->@*;

      # Call next with no callback provided. Marks end or data
      $next->(\@buffer, $cb) unless $cb;
    }
  }
}

# The inputs are consumbed by any middleware next in the normal chain
# The iputs are copied for each of the tees.
# Tees are run asynchrounously
#
sub io_tee {
  my @tees=@_;
  my @buffers;

  for(@tees){
    push @buffers, [];
  }

  sub {
    my ($next, $index, @options)=@_;
    sub {
      my $cb=$_[1];
      # tees are schedualed
      for(0..@tees-1){
        # Copy inputs to each of the buffers
        push $buffers[$_]->@*, $_[0]->@*;
        asap($tees[$_], $buffers[$_], $cb);
      }

      # Call next syncrhonously
      &$next;
    }
  }

}



use Sub::Middler;

# Backtick is like the system qx or `` operators in vanilla perl.
# Here the on_result callback is called with the accumualted output from the command
# The $? varible is set before executing the callback to check for success
sub backtick {
  my $cmd=shift;
  my $on_result=shift;


  my $buffer="";
  my $status;
  my $pid;

  my @io;
  my $join=0;

  my $do_result=sub {
	  $join++;
	  return if $join < 2;
	  # Close the io
      if(ref($on_result) eq "ARRAY"){
        my $m=linker $on_result;

        local $?=$status;
        $m->([$buffer],undef);
      }
      elsif(ref($on_result) eq "CODE"){
        local $?=$status;
        $on_result->([$buffer], undef);
        
      }
      
      	IO::FD::close($io[0]->fh);
	$io[0]->destroy();
	IO::FD::close($io[1]->fh);
	$io[1]->destroy();
	IO::FD::close($io[2]->fh);
	$io[2]->destroy();
  };

  sub_process $cmd, 
  sub {
    # parent continuation
    @io=@_;

    $pid=$io[3];

    # Back tick handles stadard out only
    $io[1]->on_read=sub {
      $buffer.=$_[0][0]; $_[0][0]="";
    };

    $io[1]->on_eof=sub {
      $do_result->();
    };


    # Consume the error stream
    $io[2]->on_read=sub {
      $_[0][0]="";
    };

    # Start readers
    $io[1]->start;
    $io[2]->start;

    # return the pid of th child process
    #$io[3];
    $pid;

  },
  sub {
    # On child cpmplete
      my $a=shift;

      # Save the status and pid of the process. We might have a reading to do however
      ($status, $pid)=$a->@*;
      $do_result->();

  };

}


# Run A command
# executes the on_result callback with the status code of the child process. No IO capturing is done
# The status is locally set to the $? variable before calling
#
sub system ($;$){

}

# Fork this process. setup broker/node for communications via pipes
# 
sub worker {
  #sub_process;
}



sub asay ($;@){
  my $w=shift;

  $w->write([join("", @_, "\n")], undef);
  $w;
}

sub asay_now ($;@){
	&asay->flush();
}

sub aprint ($;@){
  my $w=shift;
  $w->write([join("", @_, "")], undef);
  $w;
}

sub aprint_now ($;@){
	&aprint->flush();
}



sub adump ($;@){
  my $w=shift;
  require Data::Dump::Color;
  $w->write([Data::Dump::Color::dump(@_)."\n"], undef);
  $w;

}
sub adump_now($;@){
    &adump->flush();
}

sub _make_pool {
	my $preallocate=shift;
	asay $STDERR, "CALLED MAKE_POOL WITH $preallocate";
  # BOOTSTRAP THE POOL
  unless(defined $uSAC::Main::POOL){
    
	asay $STDERR, "No pool... create one";
    my %fds;
    my $rpc={
      eval=>sub {
        eval shift;
      },
      getaddrinfo=>sub {

        DEBUG and asay $STDERR, "$$ CALLED GETADDRINFO with @_". Dumper (@_); 
        my $input=decode_meta_payload $_[0], 1;
        #DEBUG and asay $STDERR, "$$ DECODED ". Dumper($input);

        my $return_out="";
        my @results;

        asay $STDERR, "$$ before getaddrinfo call";
        my $rc;
        #use feature "try";
        #try {
          $rc=Socket::More::Lookup::getaddrinfo($input->{host}, $input->{port}, $input->{hints}, \@results);
          #}
          #catch($e){
          #asay $STDERR, $e;
          #}
          #asay $STDERR, "$$ after getaddrinfo call";
        unless (defined $rc){

        }
        #DEBUG and asay $STDERR, "$$ Results ". Dumper (\@results);
        $return_out=encode_meta_payload \@results, 1;
      },

      getnameinfo=>sub {
        DEBUG and asay $STDERR, "CALLED getnameinfo"; 

        my $input=decode_meta_payload $_[0],1;

        my $return_out="";
        my @results;

        my $rc=Socket::More::Lookup::getnameinfo($input->{addr}, my $host="", my $port="", $input->{flags});
        unless (defined $rc){

        }
        $return_out=encode_meta_payload {host=>$host, port=>$port}, 1;
      },

      file_open => sub {
        DEBUG and say STDERR "$$ CALLED FILE OPEN with", Dumper (@_);
        my $input=decode_meta_payload $_[0], 1;

        DEBUG and say STDERR "$$ DECODED ". Dumper($input);

        my $return_out="";

        #asay $STDERR, "$$ before file open call";
        #
        my $fd;
        # Opend with cache ?


        my $data="";
        # Read from start if no file position given
        # TODO: maybe always read a min block size...?  one less argument to pass
        # then let the recieving process piece it together?
        #my $rc=IO::FD::open($fd, $input->{mode}, $input->{path});
        my $rc=open($fd, $input->[0]{mode}//"<",$input->[0]{path});

        #say STDERR  "---CREATED FILE hNAlDE: ", $fd, "FOre worker ", $uSAC::Main::Worker;
        my $fid=pack "LL", $$, time;
        $fds{$fid}=$fd;

        # Prevent worker from shrinking/ exiting as we need to rememeber state
        unless (defined $rc){

        }
        $return_out=encode_meta_payload {fid=>$fid, rc=>$rc, error=>$rc? undef :$!}, 1;
      
      },

      file_close => sub {
        #DEBUG and asay $STDERR, "$$ CALLED GETADDRINFO with @_". Dumper (@_); 
        my $input=decode_meta_payload $_[0], 1;
        #DEBUG and asay $STDERR, "$$ DECODED ". Dumper($input);

        my $return_out="";

        #asay $STDERR, "$$ before file read call";
        my $fd=delete $fds{$input->[0]{fid}};
        # Opend with cache ?
      
        my $data="";
        # Read from start if no file position given
        # TODO: maybe always read a min block size...?  one less argument to pass
        # then let the recieving process piece it together?
        #
        my $rc=close($fd);
      

        unless (defined $rc){

        }
        $return_out=encode_meta_payload {rc=>$rc, error=>$!}, 1;

      },

      file_read=>sub {

        #D
        #EBUG and asay $STDERR, "$$ CALLED GETADDRINFO with @_". Dumper (@_); 
        my $input=decode_meta_payload $_[0], 1;
        DEBUG and say STDERR "$$ DECODED for read ". Dumper($input);

        my $return_out="";

        #asay $STDERR, "$$ before file read call";
        my $fd=$fds{$input->[0]{fid}};

        #say STDERR  "---LOCATING FILE hNAlDE: ", $fd;
        # Opend with cache ?
      
        my $data="";
        # Read from start if no file position given
        # TODO: maybe always read a min block size...?  one less argument to pass
        # then let the recieving process piece it together?
        #
        my $rc=sysread($fd, $data, $input->[0]{length}//4096);
      

        unless (defined $rc){

        }
        $return_out=encode_meta_payload {data=>[$data], rc=>$rc, error=>$rc? undef: $!}, 1;
      },

      file_write=>sub {

        #DEBUG and asay $STDERR, "$$ CALLED GETADDRINFO with @_". Dumper (@_); 
        my $input=decode_meta_payload $_[0], 1;
        #DEBUG and asay $STDERR, "$$ DECODED ". Dumper($input);

        my $return_out="";
        my @results;

        asay $STDERR, "$$ before file write call";
        my $fd=$fds{$input->{fid}};
        # Opend with cache ?
      
        my $data="";
        #TODO: if no position ... append
        my $rc=IO::FD::pwrite($fd, $input->{data}, $input->{file_position});
      
        unless (defined $rc){

        }
        #DEBUG and asay $STDERR, "$$ Results ". Dumper (\@results);
        $return_out=encode_meta_payload {rc=>$rc, error=>$!}, 1;
      },

      path_create=>sub {
        my $input=decode_meta_payload $_[0], 1;
	my $options=pop @$input;
	$options//={};
	$options->{error}= \my $error;
	my $return_out;
	
	#say STDERR " MAKEING PATH FOR ", Dumper $input, $options;
	my @results = make_path (@$input, $options);
	#say STDERR Dumper @results, $options;

	#say STDERR " RESULTS IN WORKER ", @results;
        $return_out=encode_meta_payload {results=>\@results, error=>$options->{error}->$*}, 1;
      },

      remove_tree=>{

      }


    };
    $uSAC::Main::POOL=uSAC::Pool->new(rpc=>$rpc, preload=>$preallocate);
  }
  $uSAC::Main::POOL;
}

sub getaddrinfo {
  my ($host, $port, $hints, $cb, $error)=@_;
  my $pool=_make_pool;
  #DEBUG and asay $STDERR, "===getaddinfo args ".Dumper $host,$port, $hints;
  my $h={
    flags=>$hints->{flags}, family=>$hints->{family}, socktype=>$hints->{socktype}, protocol=>$hints->{protocol}, address=>$hints->{address}, port=>$hints->{port}
  };
  my $enc=encode_meta_payload {host=>$host, port=>$port, hints=>$h}, 1;
  my $__cb=sub {
      DEBUG and asay $STDERR, "$$ Callback in getaddinfo";
      #DEBUG and asay $STDERR, Dumper @_;
      my $p=decode_meta_payload $_[0], 1;
      #DEBUG and asay $STDERR, Dumper $p;
    $cb->(@$p)
  };
  $pool->rpc("getaddrinfo", $enc, $__cb, $error);
}

sub getnameinfo {
  my ($addr, $flags, $cb, $error)=@_;
  my $pool=_make_pool;
  my $enc=encode_meta_payload {addr=>$addr, flags=>$flags},1;
  my $__cb=sub {
    my $d=decode_meta_payload $_[0],1;
    $cb->($d->{host}, $d->{port});
  };
  $pool->rpc("getnameinfo", $enc, $__cb, $error);
}



# Open files
sub io_file_open {
  my ($fid, $error)=@_;

  #adump $STDERR, "io_file_open_wrapper";

  my $pool=_make_pool;
  sub {
    my ($next, $index, @options)=@_;
    #adump $STDERR, "io_file_open_linker ", @_;
    sub {
      #adump $STDERR, "io_file_open";
      my $cb=$_[$#_];
      my $enc=encode_meta_payload $_[0], 1;
      my $__cb=sub {
        DEBUG and asay $STDERR, "$$ Callback in file_open", Dumper @_;;
        #DEBUG and asay $STDERR, Dumper @_;
        my $p=decode_meta_payload $_[0], 1;


        # call next with generated fid
        $$fid=$p->{fid};
        DEBUG and asay $STDERR, "$$ Callback in file_open", Dumper $p;;
        $next->([], $cb);
      };

      # Call sticky_rpc
      $pool->sticky_rpc("file_open", $enc, $__cb, $error);
    }
  }
}

sub io_file_close {
  my ($fid, $error)=@_;
  my $pool=_make_pool; 
  sub {
    my ($next, $index, @options)=@_;
    sub {
      #adump $STDERR, "io_file_close";
      # First argument is the fid, remainder is data
      #close the file and call next, Only Close the file if NO CALLBACK is
      &$next if $_[1];

      my $cb=$_[$#_];

      #specified
      my $args=$_[0];
        $_[0]=[];
      my $enc=encode_meta_payload [{fid=>$$fid}], 1;
      my $__cb=sub {

        DEBUG and asay $STDERR, "$$ Callback in file_close";
        #say STDERR "FILE CLOSE in $$ ". Dumper $args;
        my $p=decode_meta_payload $_[0], 1;

        $$fid=undef;
        $next->($args, my $c=undef);
      };
      $pool->sticky_rpc("file_close", $enc, $__cb, $error);
    }
  }
}

#link  file_read, $accumulate $dispatch
sub io_file_read {
  my ($fid,  $error)=@_;
  my $pool=_make_pool;
  sub {
    my ($next, $index, @options)=@_;
      # Setup variables to allow callback to read more from file
      my $__cb;
      my $enc;
      my $__wid;
      my $internal_cb=sub {
        $pool->sticky_rpc("file_read", $enc, $__cb, $error, $__wid);
      };
      $__cb=sub {
        DEBUG and say STDERR "$$ Callback in file_read";
        #DEBUG and asay $STDERR, Dumper @_;
        my $p=decode_meta_payload $_[0], 1;
        #DEBUG and asay $STDERR, Dumper $p;
        #$cb->($p);
        if($p->{rc}){
          #say STDERR "RC non zero. call internal";
          $next->($p->{data}, $internal_cb);
        }
        else {

          #say STDERR "RC zero. call normal callback?";
          $__wid=undef;
          $next->($p->{data}, my $c=undef);
        }
      };

    sub {
      #say STDERR "io_file_read";
      
      unless($__wid){
        # Decode sthe file id once
        $__wid=unpack "L", $$fid;
      #my $cb=$_[$#_];
        $enc=encode_meta_payload [{fid=>$$fid}], 1;
      }
      #$internal_cb->();
      $pool->sticky_rpc("file_read", $enc, $__cb, $error, $__wid);
    }
  }
}

sub io_file_write{
  my ($fid, $error)=@_;
  my $pool=_make_pool;
  sub {
    my ($next, $index, @options)=@_;
    sub {
      my $cb=$_[$#_];
      my $enc=encode_meta_payload {fid=>$$fid, data=>$_[0]}, 1;
      my $__cb=sub {
        DEBUG and asay $STDERR, "$$ Callback in file_write";
        #DEBUG and asay $STDERR, Dumper @_;
        my $p=decode_meta_payload $_[0], 1;
        #DEBUG and asay $STDERR, Dumper $p;
        #$cb->($p)
        $next->($p, $cb);
      };
      $pool->rpc("file_write", $enc, $__cb, $error);
    } 
  }
}


sub io_file_slurp {
  my ($error)=@_;
  my $fid="";
  (
    io_file_open (\$fid, $error),
    io_file_read (\$fid, $error),   # uses the id from file open
    #io_accumulate,   
    io_file_close (\$fid, $error),
  )
}

sub io_file_spurt {
  my ($path, $cb, $error)=@_;
  # open
  # write by chunks
  # execute callback
}

# Create a path on the file system
sub path_create {
  my @options=@_;
  my $error=pop @options;
  my $cb=pop @options;

  my $pool=_make_pool;
  my $enc=encode_meta_payload \@options,1;
  my $__cb=sub {
    my $d=decode_meta_payload $_[0],1;

    $cb->($d->{results}, $d->{error});
  };
  $pool->rpc("path_create", $enc, $__cb, $error);

}

# Remove a path from the file system
sub path_remove {

}

sub file_open {
  my ($mode, $path, $cb, $error)=@_;

  #adump $STDERR, "io_file_open_wrapper";

  my $pool=_make_pool;
  my $enc=encode_meta_payload $_[0], 1;
  my $__cb=sub {
	  DEBUG and asay $STDERR, "$$ Callback in file_open", Dumper @_;;
	  #DEBUG and asay $STDERR, Dumper @_;
	  my $p=decode_meta_payload [$path], 1;


	  # call next with generated fid
	  my $fid=$p->{fid};
	  DEBUG and asay $STDERR, "$$ Callback in file_open", Dumper $p;;
	  $cb->($fid);
  };

  # Call sticky_rpc
  $pool->sticky_rpc("file_open", $enc, $__cb, $error);
}

sub file_close {
  my ($fid, $cb, $error)=@_;
  my $pool=_make_pool; 
      my $enc=encode_meta_payload [{fid=>$fid}], 1;
      my $__cb=sub {
        DEBUG and asay $STDERR, "$$ Callback in file_close";
        #say STDERR "FILE CLOSE in $$ ". Dumper $args;
        my $p=decode_meta_payload $_[0], 1;

	$cb->();
      };
      $pool->sticky_rpc("file_close", $enc, $__cb, $error);
}




1;
