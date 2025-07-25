#!/usr/bin/env usac --backend AnyEvent

use uSAC::IO;
use Data::Dumper;
use Socket::More::Constants;
my $do_it;
my $count=0;
$do_it=sub {
  $count=$count+1;
  exit if $count>=100;

  asay $STDERR , "$$ ---DO NEXT--- $count";
uSAC::IO::getaddrinfo("google.com",80, {}, sub {
    asay $STDERR, "GAI RETURN--------";
    asay $STDERR, Dumper @_[0];
    uSAC::IO::getnameinfo($_[0]{addr}, NI_NUMERICHOST|NI_NUMERICSERV, sub {
        asay $STDERR, "GNI RETURN--------";
        asay $STDERR, Dumper @_;
        #timer 1,0, $do_it;
        asap $do_it;
      });
  },
  sub {
    asay $STDERR, "ERROR IN top level call"
  }
);
};
$do_it->();
$do_it->();
$do_it->();
$do_it->();
1;
