use v5.36;
use uSAC::IO;

use Data::Dumper;
use Sub::Middler;

uSAC::IO::backtick "ls -al", linker 
  &uSAC::IO::io_lines => 
  &uSAC::IO::io_upper => 
  #&uSAC::IO::io_grep(qr/GITHUB/) => 
  &uSAC::IO::io_map( sub {lc $_}) => 
  sub { my $next=$_[0];  sub {
		  #say STDERR " GOT IT";
      #say STDERR Dumper @_;
      #_[0][0];
      &$next;
    }} => 
  sub {say join "|\n", @{$_[0]}};

  #while(1){sleep 1; say "slleep"}
