package uSAC::REPL;

# read input and execute
use feature ":all";
use uSAC::IO;
use Data::Dump::Color qw(dump);
use Error::Show;
no warnings "experimental";

my $reader;#= \$STDIN; #$uSAC::IO::STDIN; #uSAC::IO::reader fileno(STDIN); 
my $line="";

sub start {
  return if $reader;
  $reader= $STDIN; #$uSAC::IO::STDIN; #uSAC::IO::reader fileno(STDIN); 

  $reader->on_read=sub {
    #$reader->pause;
    #$reader->on_read=undef;
    # Consume input buffer
    my $line=$_[0][0];
    $_[0][0]="";
    asap sub {
      local $@="";
      my $res;
      {
        #package main;
        $res=eval "sub { $line }";
      }

      if($@){
        # handle syntax errors
        asay $STDERR, "$$ ERROR in eval: $@";
        asay $STDERR, Error::Show::context error=>$@, program=>$line;
      }
      else {
        # Print results
        asay $STDERR, dump $res->();
      }
      #$reader->start;
    };

  };


  #Start reader
  $reader->start;

  $started=1;
}

sub pause{
  return unless $reader;
  $reader->pause;
  $reader=undef;
}

1;

