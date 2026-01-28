use v5.36;
use uSAC::IO;

use Sub::Middler;

uSAC::IO::backtick "ls -al", linker 
  uSAC::IO::io_lines => 
  uSAC::IO::io_upper => 
  #uSAC::IO::io_grep(qr/GITHUB/) => 
  uSAC::IO::io_map( sub {lc $_}) => 
  sub { my $next=$_[0];  
    sub {
		  #say STDERR " GOT IT";
     while($_[0]->@*){

       $_=shift $_[0]->@*;
      adump $STDERR, "a=-=-=-$_" 
    }

      #_[0][0];
      &$next;
    }
  } => 
  sub {
    # asay $STDERR, join "|\n", @{$_[0]}
  };

  #while(1){sleep 1; say "slleep"}
