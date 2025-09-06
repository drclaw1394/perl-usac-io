use v5.36;
use Test::More;
use uSAC::IO ();

use Socket::More;
use Socket::More::Constants;
#use Socket::More::Lookup ();
use POSIX qw<strerror>;

use Socket ();
use Data::Dumper;

my $host="::1";#"localhost";#'127.0.0.1';
my $port=0;;

my $mut=0;
sub mut {
  $mut++;
  if($mut==2){
    done_testing;
    exit(0);
  }
}
my $err= sub {
    asay $STDERR, "Error on socket $_[0], ", $_[1];
    asay $STDERR, Dumper @_;
    done_testing();
    exit(-1);
  };
my $a;
my $hints;
$hints={port=>$port, address=>$host, socktype=>SOCK_STREAM, protocol=>IPPROTO_TCP, flags=>0,
  data=>{
    on_socket=>\&bind,

    on_error=>$err,

    on_bind=> sub {
      ok 1, "on bind";
      my $bfh=$_[0];
      ok defined($bfh), "Bind socket created";
      &uSAC::IO::listen;
    },

    on_listen=>sub {
      ok 1, "on listen";
      &uSAC::IO::accept;
      # Setup client connect to this hint
      &do_connect;
    },

    on_connect=>sub {
      my $socket=$_[0];
      asay $STDERR, "connected";
      ok 1, "connected";
      mut;
    },

    on_accept =>sub {
      ok 1, "on accept";
      asay $STDERR, "on_accept";
      mut;
    }
  },

};



# Start off with the bind of the server
uSAC::IO::socket_stage $hints;#, \&uSAC::IO::bind;


# This sub is called when server socket is listening and accepting
#
sub do_connect {
  my (undef, $hints)=@_;
  asay $STDERR, "======$$ Made it to do_connect";
  $STDERR->flush;
  uSAC::IO::socket_stage $hints, \&uSAC::IO::connect;

}

#timer 4, 0 , sub {asay $STDERR, "ljkadslkjasdlfkjasldkjfalskdjfalksdjf"};


