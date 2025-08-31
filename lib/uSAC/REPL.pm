package uSAC::REPL;

use feature "try";
use Error::Show;
use uSAC::Worker;
use IO::FD;
use uSAC::IO;
use Data::FastPack::Meta;

my $repl_worker;
sub start {
  return if $repl_worker;
  $STDERR->write(["Starting REPL ".time."\n"], sub {});

  # Duplicate standard IO, BEFORE forking so we can interact directly with
  # terminal
  #

  my $new_in=IO::FD::dup(0);
  my $new_out=IO::FD::dup(1);
  my $new_err=IO::FD::dup(2);

  # Flush
  $STDOUT->write([""], sub {});
  $STDERR->write([""], sub {});
  #my $write=writer $new_err;

  # Create a worker, wthe work paramenter is the setup
  # The rpc object is adds the method
  #
  $repl_worker=uSAC::Worker->new(
    work=>sub{
      package uSAC::REPL;
      require Term::ReadLine;
      open(our $stdin, "<&=$new_in") or die $!;
      open(our $stdout, ">&=$new_out") or die $!;

      # Create a term using our inputs and outputs
      our $TERM = Term::ReadLine->new('uSAC REPL', $stdin, $stdout);
    },

    rpc=>{
      readline=>sub {
        package uSAC::REPL;

        my $prompt=decode_meta_payload $_[0], 1;
        $prompt=$prompt->{prompt};

        #uSAC::IO::asay $STDERR, "CALLED readline with $prompt"; 
        my $line;
        if( defined ($line = $TERM->readline($prompt)) ) {
          $TERM->addhistory($line) if /\S/;
        }

        encode_meta_payload {line=>$line}, 1;
      }
    },

    on_complete=> sub{
      asay $STDERR, "WORKER COMPLETE------------sdasdfasdf";
      $repl_worker=undef;
    }
  );

  my $prompt=encode_meta_payload({prompt=>"--->"},1);
  my $repl;
  $repl=sub {
    #asay $STDERR, "SUB REF TO START REPL";
    $repl_worker->rpc("readline", $prompt,
      sub {
        #asay $STDERR, "REPL callback";
        my $line=decode_meta_payload $_[0], 1;
        $line=$line->{line};

        #asay $STDERR, $line;
        asap sub {
          try{
            package main;
            local $@;
            $res=eval "sub { $line }";
            die $@ if $@;

            asay $STDOUT, dump $res->();
          }
          catch($e){
            # handle syntax errors
            asay $STDERR, "$$ ERROR in eval: $e";
            asay $STDERR, Error::Show::context error=>$e, program=>$_line;
          }
          asap $repl;
        }
      },
      sub {
        asay $STDERR, "ERROR: $line";
        asap $repl;
      }
    );
  };
  asap $repl;
}

sub stop {
  asay $STDERR, "Stopping REPL";
  $repl_worker->close;
}

1;

