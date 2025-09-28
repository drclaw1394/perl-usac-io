# Wrapper around a main script to remove setup of event system code

package LMain;
# The LMain pacakge import the Log::ger log routnies. These are dynamicall
# inserted by Log::ger so can not be accessed in the Log::ger package namesapce
# This way the same log_* names can be used with minimal changes  and prevents
# recursive calls
#
use Log::ger;
use Log::ger::Output "Screen",use_color=>0;
use Log::OK {
  lvl=> "info",
  opt=>"verbose"
};

package main;
use uSAC::Util;
use Time::HiRes qw<time>;
use uSAC::IO;
use Data::Dump::Color qw(dump);
use Math::Trig;
use Sub::Middler;


package uSAC::Main;
# Main package. This is where the magic happens.
# Setsup run loops, logging, IO readers/writers..

use feature "try";
no warnings "experimental";
use Sub::Middler;
use uSAC::IO;# ();

use uSAC::Pool;


our $POOL;
our $USAC_RUN=1;
our $WORKER;


# Create Setup the default broker entry points
#
our $Default_Broker;

our $broadcaster;
our $listener;
our $ignorer;

my $broker_ok;
try {
  require uSAC::FastPack::Broker;
  $broker_ok=1;
}
catch($e){
  # No broker.. probably not installed
  warn "uSAC::FastPack::Broker not installed. Internal messaging will fail";
}


if($broker_ok){
  $Default_Broker=uSAC::FastPack::Broker->new;

  $broadcaster=*usac_broadcast=$Default_Broker->get_broadcaster;
  $listener=*usac_listen=$Default_Broker->get_listener;
  $ignorer=*usac_ignore=$Default_Broker->get_ignorer;
  $SIG{__WARN__}=sub {
    #$broadcaster->("usac/log/warn", "WARN: ".$_[0]);
  }
}
else {

  $broadcaster=*usac_broadcast=sub {};
  $listener=*usac_listen=sub {};
  $ignorer=*usac_ignore=sub {};
}


use Error::Show;
sub _setup_log {
  
  usac_listen(undef, "usac/log/fatal",   sub {
      asay $STDERR, "\033[1;31m$$ $_[0][1][0][2]\033[0m";
  },
  "exact"
);
  usac_listen(undef, "usac/log/error",   sub {
      asay $STDERR, "\033[31m$$ $_[0][1][0][2]\033[0m";
  },
  "exact");
  usac_listen(undef, "usac/log/warn",   sub {
      asay $STDERR, "\033[33m$$ $_[0][1][0][2]\033[0m";
  },
  "exact");
  usac_listen(undef, "usac/log/info",   sub {
      asay $STDERR, "\033[32m$$ $_[0][1][0][2]\033[0m";
  },
  "exact");
  usac_listen(undef, "usac/log/debug",   sub {
      asay $STDERR, "\033[35m$$ $_[0][1][0][2]\033[0m";
  },
  "exact");
  usac_listen(undef, "usac/log/trace",   sub {
      #asay $STDERR, $$." ".$_[0][1][0][2];
      asay $STDERR, "\033[36m$$ $_[0][1][0][2]\033[0m";
  },
  "exact");
}

sub _cli{
  #print  "Called from cli\n";
  my %options;
  #getopts("e:E:C:I:M:",\%options);
  #for my($k,$v)(%options){
  #print "$k=> $v\n";
  #}
  # Specified from commandline
  # Perl has already removed the script path from ARGV
  #
  # Figure out the script the user whats to run from.
  ###############################
  # my $c=0;                    #
  # my $index=0;                #
  # my $script;                 #
  # for(@ARGV){                 #
  #   if(/-.*/){                #
  #     $c=1;                   #
  #     $index++;               #
  #                             #
  #   }                         #
  #   if($c){                   #
  #     # preceding switch      #
  #     $index++;               #
  #     $c=0;                   #
  #   }                         #
  #   else {                    #
  #     # No preceding switch.. #
  #     # we found it           #
  #     $script=$_;             #
  #     last;                   #
  #   }                         #
  # }                           #
  #                             #
  # $script=$ARGV[$index];      #
  ###############################

  #my $plapp= __FILE__; #Path to this file!
  #splice @ARGV, $index, 0,  $plapp;

  # Now simply do an exec
  #exec $^X, @ARGV;
}

sub _called {
  #print  "Called from code\n";
  # called from program

}

sub import {
  # Import accoring to cli or in file call usage 
  (defined $caller[LINE])?  &_called: &_cli;
}




# Redefine exit to call f
our $exit_code;
our $restart_loop=1;
our $worker_flag=0;

#  Pre declare the main routine. It is expected in the users code
#sub main;
my $script=$0;

our $worker_sub;
my $parent_sub;

sub _main {
  use feature "try";
  # setup Boot strap timers and in readers/writers
  #
  $STDIN = reader(0);
  $STDOUT= writer(1);
  $STDERR= writer(2);

  # Force built in file handles to auto flush. This make writing unbuffered and synchrounous.
  #
  STDERR->autoflush(1);
  STDOUT->autoflush(1);


  # Setup default broker/messaging. Add listeners for logging
  #
  _setup_log;



  # If called with an argument, it is hex encoded perl code
  #
  my $inline=shift;
  if($inline){
    $inline=pack "H*", $inline;
  }
  
  #print "ARGV in MAIN: @ARGV\n";
  # Perl has consumed all the switches it wants. So the first item is the script
  my $script//=shift @ARGV;

  if(!$script and !$inline){
    aprint  $STDERR, "No script file given. Entering REPL\n";
    my $p=`which usac-repl`;
    chomp($p);
    $script= $p;
  }

  ###############################################################################################
  # # NOTE: THe worker structure is based areound a template worker. If the                     #
  # # process was started 'fresh' and executed as a template it setups the                      #
  # # communications to allow starting grand children based on the template                     #
  # #                                                                                           #
  # my $worker_flag=!!%uSAC::WorkerSwitch::;                                                    #
  # if($worker_flag){                                                                           #
  #                                                                                             #
  #                                                                                             #
  #   die "Cannot run as worker in repl mode" if $script=~/usac-repl/;                          #
  #   die "Cannot run as worker with tty" if -t STDIN or -r STDOUT;                             #
  #                                                                                             #
  #   require uSAC::Worker;                                                                     #
  #   # Set up as a worker process (for rpc calls from parent)                                  #
  #   # But only if this isn;t an interactive se                                                #
  #   Log::OK::TRACE and asay $STDERR,"setup workers ";                                         #
  #   # Test if the worker namespace is present. If so we setup the STD IO to as a worker comms #
  #   uSAC::Worker::setup_template();                                                           #
  #   Log::OK::TRACE and asay $STDERR," after setup workers ";                                  #
  # }                                                                                           #
  ###############################################################################################



  #print STDERR "WORKING WITH script $script\n";
  $0=$script;

  $parent_sub=sub { 
          #die "NO script to run" unless -e $script;
            local $@=undef;
            local $!=undef;

            # A relative path must have "./" prepended to it to run
            # like normal perl do to the 'do script'
            # Let absolute paths and ../ types alone
            my $res;
            {
              package main;
              $res=eval $inline;
            }

            if($res == undef and $@){
              # Compile error
              #print STDERR "COMPILE ERROR: $@";
              asay $STDERR, Error::Show::context $@;
              exit;
            }

            
            $res=undef;

            local $@=undef;
            local $!=undef;

            if($script){
              if(($script!~m{^/}) and ($script!~m{^\.{1,2}/})){
                $script="./$script"
              }

              {
                package main;
                $res=do $script;
              }

              if(!defined $res and $@){
                die $@;
                # Compile error
                #asay $STDERR, "RRERROR: $@";
                #exit;
              }
              elsif(!defined $res and $!){
                # Access error
                asay $STDERR, "error $script: $!\n"; 
                exit;  # This stops the loop
              }
              else {
                #print  STDERR "No script file. Entering REPL\n";
              }
            }

            # Start even processin on read stream
            #$STDIN->start;
      };


    _do_it();
}
  sub _do_it {
    $uSAC::Main::POOL->close if $uSAC::Main::POOL;
    $Default_Broker->_post_fork;
    $Default_Broker->broadcast(undef,"post-fork", 1);
    $POOL=undef;
    uSAC::IO::asap($worker_sub?$worker_sub:$parent_sub, $$);  # Call user code in a schedualled fashion
    $worker_sub=undef;
    # NOTE: THis while loop is important. no really any easy way to recall the run loop, without it
    # Run loop is recalled on fork ( so for parent and child)
    while($USAC_RUN){
      uSAC::IO::_pre_loop;          # Setup up event loop ie create cv or do nothing
      uSAC::IO::_post_loop;     # run event loop ie wait for cv or call  run
    }
    CORE::exit($exit_code);  # Exit perl with code
  }

1;
