# Wrapper around a main script to remove setup of event system code

package uSAC::Main;
use feature "try";
no warnings "experimental";
#use feature "say";
use Log::ger;
use Log::ger::Output "Screen";
use Log::OK {
  lvl=> "info",
  opt=>"verbose"
};


use Sub::Middler;
use uSAC::IO;# ();





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
    $broadcaster->("usac/log/warn", "WARN: ".$_[0]);
  }
}
else {

  $broadcaster=*usac_broadcast=sub {};
  $listener=*usac_listen=sub {};
  $ignorer=*usac_ignore=sub {};
}


use Error::Show;
sub _setup_log {
  
  usac_listen("usac/log/fatal",   sub {
      log_fatal join "\n", $_[0][1][0][2];
  });
  usac_listen("usac/log/error",   sub {
      log_error join "\n", $_[0][1][0][2];
  });
  usac_listen("usac/log/warn",   sub {
      log_warn join "\n", $_[0][1][0][2];
  });
  usac_listen("usac/log/info",   sub {
      log_info join "\n", $_[0][1][0][2];
  });
  usac_listen("usac/log/debug",   sub {
      log_debug join "\n", $_[0][1][0][2];
  });
  usac_listen("usac/log/trace",   sub {
      log_trace join "\n", $_[0][1][0][2];
  });
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
my @exit_args;
my $restart_loop=1;

#  Pre declare the main routine. It is expected in the users code
#sub main;
my $script=$0;

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


  my $inline=shift;
  if($inline){
    $inline=pack "H*", $inline;
  }
  
  #print "ARGV in MAIN: @ARGV\n";
  # Perl has consumed all the switches it wants. So the first item is the script
  my $script//=shift @ARGV;

  my $p=`which usac-repl`;
  chomp($p);
  if(!$script and !$inline){
    aprint  $STDERR, "No script file given. Entering REPL\n";
    $script= $p;
  }


  #print STDERR "WORKING WITH script $script\n";
  $0=$script;


  while($restart_loop--){
    #_template_process;   #
    uSAC::IO::_pre_loop;      # Setup up event loop ie create cv or do nothing
    uSAC::IO::asap(sub { 
          #die "NO script to run" unless -e $script;
            local $@=undef;
            local $!=undef;

            # A relative path must have "./" prepended to it to run
            # like normal perl do to the 'do script'
            # Let absolute paths and ../ types alone
            my $res;
            $res=eval $inline;

            if($res == undef and $@){
              # Compile error
              #print STDERR "COMPILE ERROR: $@";
              asay $STDERR, Error::Show::context error=>$@;
              exit;
            }

            
            $res=undef;

            local $@=undef;
            local $!=undef;

            if($script){
              if(($script!~m{^/}) and ($script!~m{^\.{1,2}/})){
                $script="./$script"
              }
              $res=do $script;

              if(!defined $res and $@){
                # Compile error
                asay $STDERR, "COMPILE ERROR";
                asay $STDERR, Error::Show::context error=>$@;
                exit;
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
      }
    );    # Call user code in a schedualled fashion
    #my $code=$_[0];
    uSAC::IO::_post_loop;     # run event loop ie wait for cv or call  run
  }
  CORE::exit(@exit_args);  # Exit perl with code
}

=pod
=head1 NAME
  
  uSAC::Main - Implement the main behind the scenes event loop

=head1 DESCRIPTION

Used by the L<usac> script, this prepares the backround run loop and
the funs the users script in the loop.


