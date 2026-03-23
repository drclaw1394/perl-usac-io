package uSAC::REPL;

use v5.36;
use feature "try";
use Error::Show;
use uSAC::Worker;
use IO::FD;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use uSAC::IO;
use Data::FastPack::Meta;
use uSAC::FastPack::Channel;

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
use v5.36;
use feature "try";


our $TERM;
our $stdout;
our $stdin;
our $stderr;

our $new_in;
our $new_out;
our $new_err;


my $repl_worker;
my $repl;
my $handler;
my $ch_slave;
my $broker;

my $prompt="___:";

my $perl_repl_handler=sub {
	#say STDERR  "IN PERL REPL HANDLER ", @_;
          my $line=$_[0];
          try{
            package main;
            local $@;
            my $res=Error::Show::streval "sub { no strict \"subs\"; no strict \"vars\"; $line }";
            die $@ if $@;
            my @ret=$res->();

            asay_now $STDOUT, @ret;
	    
	    #say STDERR "----RETURN FOR EVAL @ret";
	    #say STDERR "";
          }
          catch($e){
            # handle syntax errors
            asay $STDERR, "$$ ERROR in eval: $e";
            asay_now $STDERR, Error::Show::context $e;
	    #say STDERR "----ERROR FOR EVAL";
          }
          asap $repl;
        };

sub start {
  return if $repl_worker;
  $handler=shift//$perl_repl_handler;
  $broker=shift//$uSAC::Main::Default_Broker;
  $STDERR->write(["Starting REPL ".time."\n"], sub {});

  # Duplicate standard IO, BEFORE forking so we can interact directly with
  # terminal
  #

  $new_in=IO::FD::dup(0);
  $new_out=IO::FD::dup(1);
  $new_err=IO::FD::dup(2);

  # Flush
  $STDOUT->write([""], sub {});
  $STDERR->write([""], sub {});


  uSAC::FastPack::Channel->accept("repl_end_accept", $broker, sub {

      say STDERR "---- GOT A NEW CHANNEL CONNECTION IN PARENT: @_";
      my $master=$_[0];
      $master->on_data=sub {
        #asay_now $STDERR, "Data arriving at master @_";
			  my $msg=decode_meta_payload $_[0], 1;
        use Data::Dumper;
        #asay_now $STDERR, Dumper $msg;
        if($msg->{line}){
          my $line=$msg->{line};
          #asay_now $STDERR, "HAVE LINE: $line";
          try{
            package main;
            local $@;
            my $res=Error::Show::streval "sub { no strict \"subs\"; no strict \"vars\"; $line }";
            #asay_now $STDERR, $res;
            die $@ if $@;
            my @ret=$res->();

            asay_now $STDERR, @ret;

            #say STDERR "----RETURN FOR EVAL @ret";
            #say STDERR "";
          }
          catch($e){
            # handle syntax errors
            asay $STDERR, "$$ ERROR in eval: $e";
            asay_now $STDERR, Error::Show::context $e;
            #say STDERR "----ERROR FOR EVAL";
          }
        }


      };

  });


  #my $write=writer $new_err;
		
  # Create a worker, wthe work paramenter is the setup
  # The rpc object is adds the method
  #
  $repl_worker=uSAC::Worker->new(
    shrink=>0,
    work=>sub{
      # Connect back to parent with a dedicated channel
      
      $ch_slave=uSAC::FastPack::Channel->new(broker=>$broker);
      $ch_slave->connect("repl_end_accept", sub {
          say STDERR "----=-=-=-==-- GOT NEW CHANNEL CONNECTION: @_";
          my $slave=$_[0];
          $slave->on_data=sub {
            asay_now $STDERR, "Data arriving at slave @_";

          };
      });

      # Need to make stdin blocking again for readline to work .. on linux anyway
      #
      use feature "bitwise";
      package uSAC::REPL;
      #my $flags=IO::FD::fcntl $new_in, F_GETFL, 0;
      #$flags &= ~O_NONBLOCK;

      #     IO::FD::fcntl $new_in, F_SETFL, $flags;

      require Term::ReadLine;
      require Term::ReadKey;
      open($stdin, "<&=$new_in") or die $!;
      open($stdout, ">&=$new_out") or die $!;
      open($stderr, ">&=$new_err") or die $!;

      Term::ReadKey::ReadMode('cbreak', $stdin);
      # Create a term using our inputs and outputs
      $TERM = Term::ReadLine->new('uSAC REPL', $stdin, $stdout);
      
      #use Data::Dumper;
      sub my_gen_master {
      
        my ($text, $state)=@_;
        use feature "state";
        state @list;
        unless($state){
          @list=grep !/^_\</, keys %::; # remove the file names

          @list=grep /^$text/, @list;   # Prematch with the text
        }
          
        $list[$state];


      }

      sub my_gen {
        # Use local cache of object, but send requests to master to update
        my ($text, $state)=@_;
        use feature "state";
        state @list;
        unless($state){
          @list=grep !/^_\</, keys %::; # remove the file names

          @list=grep /^$text/, @list;   # Prematch with the text
        }
          
        $list[$state];

      }

      sub attempted_completion_function{
        my ($text, $line, $start, $end) = @_;
        #print $stdout Dumper $text, $line, $start, $end;
        #my @options = qw(option1 option2 option3 obese);
        #        return grep { /^\Q$text/ } @options;
        my @options=$TERM->completion_matches($text, \&my_gen);


        # Find the longest prefix
        my $shortest=$options[0];
        my $prefix=$text;
        my $index=length $text;
        for my $item(@options){
          my $count=grep {my $pos=index $_, $prefix, 0; $pos==0} @options;
          last if $count <=1;
          $index++;
          $prefix=substr $shortest, 0 , $index;
        }

        # If there isn  and eact match, return prefix first
        my @can=grep { /$prefix/ } @options;
        unshift @can, $prefix unless grep /^$prefix$/, @can;

        @can;
      }
      
      sub completion_function{
         my ($text, $line, $start) = @_;
        qw< a list of stuff>;
      }

      $TERM->Attribs->{attempted_completion_function} = \&attempted_completion_function;

      #$TERM->Attribs->{completion_function} = \&completion_function;


      my $reader=sreader(fh=>$new_in);
      $reader->on_can_read=
      sub {
        package uSAC::REPL;


        #say STDERR "D======= DOING ON READ";
	
        #my $prompt="___:";#decode_meta_payload $_[0], 1;
        #$prompt=$prompt->{prompt};

	      my $return;
        my $line;
        #$TERM->ISSTATE();
        #Term::ReadLine::Gnu::RL_STATE_TIMEOUT;
        #use Data::Dumper;
        #say STDERR Dumper $TERM->Features();
        #say STDERR $TERM->ReadLine();
        #$TERM->set_timeout(0, 100000);
        Term::ReadKey::ReadMode('restore', $stdin);
          $line = $TERM->readline();
          if( defined ($line)){
            $TERM->addhistory($line) if /\S/;
            #print $stdout "LINE from readline iis $line, with length ". length $line;
            #print $stdout "\n";
            $return=encode_meta_payload {line=>$line}, 1;
            $ch_slave->send_data($return);
            # We processed a complete line... so reset trigger
            Term::ReadKey::ReadMode('cbreak', $stdin);
            #print $stdout $prompt;
          }
          else {
            print $stdout "READLINE UNDEF\n";
            #$return=encode_meta_payload {line=>""}, 1;
            #$ch_slave->send_data($return);
          }

	$return;
  };
      $reader->start;
      #timer 0,2, sub {
        #say STDERR "NON BLOCKING TIMER";
        #};





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

  my $prompt=encode_meta_payload({prompt=>"--->"},1);
  $repl=sub {
	  #asay $STDERR, "SUB REF TO START REPL";
	  return unless $repl_worker;
	  $repl_worker->rpc("readline", $prompt,
		  sub {
			  #asay $STDERR, "REPL callback";
			  my $line=decode_meta_payload $_[0], 1;
			  $line=$line->{line};

			  asap $handler, $line;

		  },
		  sub {
			  asay $STDERR, "ERROR: @_";
			  asap $repl;
		  }
	  );
  };
  #asap $repl;
}

sub stop {
  asay $STDERR, "---Stopping REPL---";
  $repl_worker->close if $repl_worker;
  IO::FD::close $new_in;
  IO::FD::close $new_out;
  IO::FD::close $new_err;
}

1;

