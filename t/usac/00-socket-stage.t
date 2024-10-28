use v5.36;
use Test::More;
use uSAC::IO;

use Data::Dumper;

my $spec= {
  port=>0,
  family=>"AF_INET",
  interface=>"lo",
  socktype=>"SOCK_STREAM",

  data=>{
    on_spec=>sub {

      say STDERR "Got spec", Dumper @_;

      if(@_ and !defined $_[0]){
        ok 1, "Resolved ok";
        done_testing;
        exit();
      }
    },

    on_error=>sub {
      say STDERR "GOT ERROR @_";
    }

  }
};

uSAC::IO::_prep_spec $spec;

