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
    local $@="";
    my @res;
    {
      package main;
      @res=eval $_[0][0];
    }

    if($@){
      # handle syntax errors
      asay $STDERR, "ERROR: $@";
      asay $STDERR, Error::Show::context error=>$@, program=>$_[0][0];
    }
    else {
      # Print results
      asay $STDERR, dump @res;
    }

    # Consume input buffer
    $_[0][0]="";
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

