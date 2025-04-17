use v5.36;
use uSAC::IO;

use Sub::Middler;

uSAC::IO::_backtick "ls -al", linker 
#\sub { say $_[0]->@*}=>
  &uSAC::IO::_lines => 
  &uSAC::IO::_upper => 
  &uSAC::IO::_grep(qr/GITHUB/) => 
  &uSAC::IO::_map( sub {lc $_}) => 
  sub { my $next=$_[0];  sub {
      say STDERR " GOT IT",
      say STDERR $_[0][0];
      &$next;
    }} => 
  sub {say join "|\n", @{$_[0]}};

  #while(1){sleep 1; say "slleep"}
