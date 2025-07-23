#!/usr/bin/env usac --backend AnyEvent

use uSAC::IO;
use Data::Dumper;
use Socket::More::Constants;
#my $w=uSAC::Worker->new();
uSAC::IO::getaddrinfo("google.com",80, {}, sub {
    asay $STDERR, "GAI RETURN--------";
    asay $STDERR, Dumper @_[0];
    uSAC::IO::getnameinfo($_[0]{addr}, NI_NUMERICHOST|NI_NUMERICSERV, sub {
      asay $STDERR, "GNI RETURN--------";
      asay $STDERR, Dumper @_;
      exit;
      });
  },
  sub {
    asay $STDERR, "ERROR IN top level call"
  }
);

asay $STDERR, "END OR PROGRAM____";
1;
