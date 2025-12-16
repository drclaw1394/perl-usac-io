package uSAC::REPL;

use feature "try";
use Error::Show;
use uSAC::Worker;
use IO::FD;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use uSAC::IO;
use Data::FastPack::Meta;

# Add additional packages to main
package main;
################################################################
# use List::Util qw(                                           #
# reduce any all none notall first reductions                  #
# max maxstr min minstr product sum sum0                       #
# pairs unpairs pairkeys pairvalues pairfirst pairgrep pairmap #
# shuffle uniq uniqint uniqnum uniqstr head tail zip mesh      #
# );                                                           #
################################################################

#use Time::Piece;
#use Math::Complex;

package uSAC::REPL;
my $repl_worker;
my $repl;
my $handler;

my $perl_repl_handler=sub {
          my $line=$_[0];
          try{
            package main;
            local $@;
            my $res=Error::Show::streval "sub { no strict \"subs\"; no strict \"vars\"; $line }";
            die $@ if $@;
            my @ret=$res->();

            asay $STDOUT, @ret;
          }
          catch($e){
            # handle syntax errors
            asay $STDERR, "$$ ERROR in eval: $e";
            asay $STDERR, Error::Show::context $e;
          }
          asap $repl;
        };

sub start {
  return if $repl_worker;
  $handler=shift//$perl_repl_handler;
  $STDERR->write(["Starting REPL ".time."\n"], sub {});

  # Duplicate standard IO, BEFORE forking so we can interact directly with
  # terminal
  #

  our $new_in=IO::FD::dup(0);
  our $new_out=IO::FD::dup(1);
  our $new_err=IO::FD::dup(2);

  # Flush
  $STDOUT->write([""], sub {});
  $STDERR->write([""], sub {});
  #my $write=writer $new_err;
		
  # Create a worker, wthe work paramenter is the setup
  # The rpc object is adds the method
  #
  $repl_worker=uSAC::Worker->new(
    shrink=>0,
    work=>sub{

      # Need to make stdin blocking again for readline to work .. on linux anyway
      #
      use feature "bitwise";
      package uSAC::REPL;
      my $flags=IO::FD::fcntl $new_in, F_GETFL, 0;
      $flags &= ~O_NONBLOCK;
      
	    IO::FD::fcntl $new_in, F_SETFL, $flags;

      require Term::ReadLine;
      open(our $stdin, "<&=$new_in") or die $!;
      open(our $stdout, ">&=$new_out") or die $!;

      # Create a term using our inputs and outputs
      our $TERM = Term::ReadLine->new('uSAC REPL', $stdin, $stdout);



    },

    rpc=>{
      readline=>
      sub {
        package uSAC::REPL;

        my $prompt=decode_meta_payload $_[0], 1;
        $prompt=$prompt->{prompt};

	      my $return;
        #uSAC::IO::asay $STDERR, "CALLED readline with $prompt"; 
        my $line;
        if( defined ($line = $TERM->readline($prompt)) ) {
          $TERM->addhistory($line) if /\S/;
	        #print $stdout "LINE from readline iis $line, with length ". length $line;
	        #print $stdout "\n";
          $return=encode_meta_payload {line=>$line}, 1;
        }
	else {
		#print $stdout "READLINE UNDEF\n";
          $return=encode_meta_payload {line=>""}, 1;
	}

	$return;
      }
    },

    on_complete=> sub{
	    #asay $STDERR, "WORKER COMPLETE------------sdasdfasdf";
      $repl_worker=close;
      $repl_worker=undef;
    }
  );

  say STDERR " -----before sigal setup";
  #
  #Stop the parent from having a watcher on the  input
  #  $STDIN->pause;
  #$STDOUT->pause;
  #$STDERR->pause;

  signal INT=>sub {
	  #asay $STDERR, "REPL interrupt";
	 	stop();
    #$repl_worker->close;

  };

  say STDERR " -----before prompt";
  my $prompt=encode_meta_payload({prompt=>"--->"},1);
  say STDERR " -----after prompt";
  $repl=sub {
    #asay $STDERR, "SUB REF TO START REPL";
  say STDERR " -----in repl asap sub";
    return unless $repl_worker;
    $repl_worker->rpc("readline", $prompt,
      sub {
        #asay $STDERR, "REPL callback";
        my $line=decode_meta_payload $_[0], 1;
        $line=$line->{line};

        asap $handler, $line;
        
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
  asay $STDERR, "---Stopping REPL---";
  $repl_worker->close if $repl_worker;
  IO::FD::close $new_in;
  IO::FD::close $new_out;
  IO::FD::close $new_err;
}

1;

