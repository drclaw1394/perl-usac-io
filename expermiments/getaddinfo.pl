#!/usr/bin/env usac --backend AnyEvent

use uSAC::IO;
use Data::Dumper;
#my $w=uSAC::Worker->new();
uSAC::IO::getaddrinfo("google.com",80, {}, sub {
    asay $STDERR, "GAI RETURN--------";
    asay $STDERR, Dumper @_[0];
    uSAC::IO::getnameinfo($_[0][0]{addr}, 0, sub {
      asay $STDERR, "GNI RETURN--------";
      asay $STDERR, Dumper @_[0];
      });
  },
  sub {
    asay $STDERR, "ERROR IN top level call"
  }
);

asay $STDERR, "END OR PROGRAM____";
1;
