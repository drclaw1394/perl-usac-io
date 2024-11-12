# Wrapper around a main script to remove setup of event system code

package uSAC::Main;
no warnings "experimental";
#use Getopt::Std;
#use AnyEvent;


use uSAC::IO ();

use Error::Show;
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
  
  ##print "LOOP\n";
  #print "ARGV in MAIN: @ARGV\n";
  # Perl has consumed all the switches it wants. So the first item is the script
  $script=shift @ARGV;
  my $p=`which usac-repl`;
  chomp($p);
  $script//= $p;


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
	    if(($script!~m{^/}) and ($script!~m{^\.{1,2}/})){
            	$script="./$script"
	    }
            my $res=do $script;
            if(!defined $res and $@){
              # Compile error
              print  STDERR "COMPILE ERROR";
              print STDERR Error::Show::context error=>$@;
              exit;
            }
            elsif(!defined $res and $!){
              # Access error
             print STDERR "error $script: $!\n"; 
             exit;  # This stops the loop
            }
            else {
              print  STDERR "No script file. Entering REPL\n";
            }
      }
    );    # Call user code in a schedualled fashion
    uSAC::IO::_post_loop;     # run event loop ie wait for cv or call  run
  }
  #print "AT EXIT";
  CORE::exit(@exit_args);  # Exit perl with code
}

=pod
=head1 NAME
  
  uSAC::Main - Implement the main behind the scenes event loop

=head1 DESCRIPTION

Used by the L<usac> script, this prepares the backround run loop and
the funs the users script in the loop.


