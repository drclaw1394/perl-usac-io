#!/usr/bin/env usac --backend AnyEvent
use uSAC::IO;

my $r=uSAC::IO::SReader::create(fh=>fileno(STDIN));
$r->on_read= sub {
  print "READ: @_";
};

 $r->start;
 print "GOT TO END";

