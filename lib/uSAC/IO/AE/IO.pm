package uSAC::IO::AE::IO;

use strict;
use warnings;
#use v5.36;
use feature qw<try current_sub>;
no warnings "experimental";

#use Socket ":all";
#use Socket::More;
use Errno qw(EAGAIN EINTR EINPROGRESS EISCONN );
#use parent "uSAC::IO";

use Time::HiRes qw<time>;
use AnyEvent;
use IO::FD;
use IO::FD::DWIM;

our %watchers;
our %sig_watchers;

# Postpone a subroutine call
my @asap;
my @asap_args;
my $asap_timer;
my $entry;


use Data::Dumper;
our $CV;
my $will_exit;
my $tick_timer_raw;


sub _shutdown_loop {
  use v5.36;
  $CV and ($CV isa AnyEvent::CondVar) and $CV->send;
  #$CV=undef;
}

sub _exit {
  # Exit is called after raw timer, when no more watchers.  However if called
  # manually we need to force cleanup so orphaned processare are not left
  # 
  # direct call
  for(keys %watchers){
    cancel($watchers{$_});
  }
  for(keys %uSAC::IO::procs){
    uSAC::IO::sub_process_cancel($_);
  }
  for(keys %uSAC::IO::sig_watchers){
    uSAC::IO::signal_cancel($_);
  }

  $uSAC::Main::exit_code=shift//0;
  $uSAC::Main::POOL->close if $uSAC::Main::POOL;

  # Do any cleanup before exiting 
  # Mark with will_exit to prevent blocking on undefined $CV
  #
  $tick_timer_raw=undef;
  $will_exit=1;
  $uSAC::Main::USAC_RUN=0;
  _shutdown_loop;
}


sub cancel ($){
  my $w=delete $watchers{$_[0]};
  $_[0]=undef; 
  #use Error::Show;
}



# Processing sub for asap code refs.

my $asap_sub=sub {
  return unless @asap;
  # Call subs with supplied arguments.
  #
  my $entry=shift @asap;
  my $args=shift @asap_args;
  try{
    $entry->(@$args);
  }
  catch($e){
    _exception($e);
  }

  # Destroy the idle watcher/timer if nothing left to process!
  if(!@asap){
    $asap_timer=undef;

    delete $watchers{idle};
  }

};

# Schedule a code ref to execute asap on current event system.
#
sub asap ($;@){
    my ($c, @args)=@_;
    if($c){
      # only push if a sub is given. Otherwise we just use as a way to restart the asap timer
      push @asap, $c;
      push @asap_args, \@args;
    }
    #uSAC::IO::asay $STDERR, "Restarting ASAP in $$ with ".@asap." args ";

	$asap_timer//=AE::idle $asap_sub;
	#$asap_timer//=AE::timer 0.0, 0.0001, $asap_sub;
    $watchers{idle}=$asap_timer;
    1;
}

sub timer ($$$){
    my ($offset, $repeat, $sub, $no_save)=@_;
    my $s="";
    my $id=\$s;
    $watchers{$id}=AE::timer $offset, $repeat, sub{
      delete $watchers{$id} unless($repeat);
      try {
        $sub->($id)
      }
      catch($e){
        _exception($e);
      }
    };
    $id;
  }


##############################
# sub timer_cancel ($){      #
#   delete $watchers{$_[0]}; #
#   $_[0]=undef;             #
# }                          #
##############################

*timer_cancel=\&cancel;

sub signal ($$){
  my ($name, $sub)=@_;
  my $s;
  my $id=\$s;
  $sig_watchers{$id}=AE::signal $name, sub { $sub->(@_, $id)};
  $id;
}

sub signal_cancel ($){
  delete $sig_watchers{$_[0]};
  $_[0]=undef;
}

#*signal_cancel=\&cancel;

sub child ($$){
  my ($pid, $sub)=@_;
  my $s;
  my $temp;
  $temp=AE::child $pid, sub {
	  #NOTE: The asap schedualed code IS REQUIRED.  On linux is seems the
	  #callback can be executed synchronoulsy for a short process. The
	  #result is the watcher is removed before its added. ASAP fixes this
	  #
	  asap sub {
		  use Data::Dumper;
		  my $w=delete $watchers{$_[0]};

		  # Actual error code in upper 8 bits of 16 bit return value
		  #
		  $_[1]=$_[1] >> 8;

		  &$sub;
	  },@_;
  };
  $watchers{$pid}=$temp;
    $temp;
}

##############################
# sub child_cancel ($){      #
#   delete $watchers{$_[0]}; #
#   $_[0]=undef;             #
# }                          #
##############################
*child_cancel=\&cancel;





#my $id;
sub connect_addr {
  #A EINPROGRESS is expected due to non block
  my ($socket, $addr, $on_connect, $on_error)=@_;

  #$id++;
  my $s;
  my $id=\$s;
  my $retry=0;
	my $res;
    $res=IO::FD::connect IO::FD::DWIM::fileno($socket), $addr;
    $retry++;

  unless($res){
    #EAGAIN for pipes
    #EINTR ... docs say to retry? but that doesn't work... 
    # Here we wait until socket writable
    if($! == EAGAIN or $! == EINPROGRESS or $! == EINTR){
      my $cw;$cw=AE::io $socket, 1, sub {
              #Need to check if the socket has
              my $sockaddr=IO::FD::getpeername $socket;

              delete $watchers{$id};

              if($sockaddr){
                      $on_connect and $on_connect->($socket, $addr);
              }
              else {
                      #error
                      $on_error and $on_error->($socket, "$!");
              }
      };
      $watchers{$id}=$cw;
    }
    else {
      # Syncrhonous fail. reshedual
      uSAC::IO::asay $STDERR, "Synchronouse error at connect: $!";
      $on_error and asap $on_error, $socket, "$!";
    }
    return;
  }
  else {
    # Syncrhonous connect. reshedual
    asap $on_connect, $socket, $addr if $on_connect;
  }

	$id;
}

sub connect_cancel ($) {
	delete $watchers{$_[0]};
}

#take a hostname and resolve it
my $resolve_watcher;
sub resolve {
#####################################################################################
#         unless($resolve_watcher){                                                 #
#                                                                                   #
#                 my $dns = Net::DNS::Native->new(pool => 1, notify_on_begin => 1); #
# my $handle = $dns->inet_aton("google.com");                                       #
# my $sel = IO::Select->new($handle);                                               #
# $sel->can_read(); # wait "begin" notification                                     #
# sysread($handle, my $buf, 1); # $buf eq "1", $handle is not readable again        #
# $sel->can_read(); # wait "finish" notification                                    #
# # resolving done                                                                  #
# # we can sysread($handle, $buf, 1); again and $buf will be eq "2"                 #
# # but this is not necessarily                                                     #
# my $ip = $dns->get_result($handle);                                               #
#####################################################################################
	
}

################
# sub accept { #
#              #
# }            #
################

sub cancel_accept {

}

# Code to setup event loop before it starts
sub _pre_loop {
  $will_exit=undef;
  # Create a cv; 
  $CV=undef;
  $CV=AE::cv;
  # unless $CV;
  return;
}

sub _post_loop {
  # Create a tick timer, which isn't part of the normal watcher list
  # When no watchers are present, 
  unless($tick_timer_raw){
    $tick_timer_raw=1; # Synchronous true until asap is called
    #uSAC::IO::asay $STDERR, "in tick timer check----";
    asap sub {
	    #uSAC::IO::asay $STDERR, "---DOING ASAP FOR TICK TIMER=======";
      my $id=timer 0, 0.5, sub {
	      #uSAC::IO::asay $STDERR, "--raw timer callback--";
        $uSAC::IO::Clock=time;
	#uSAC::IO::asay $STDERR, "WATCHERS for $$ ARE ". join " ", %watchers;
	#uSAC::IO::asay $STDERR, "PROCs for $$ ARE ". join " ", %uSAC::IO::procs;
        #print STDERR "\n";
        _exit unless keys %watchers;
      };

      $tick_timer_raw=delete $watchers{$id};
    };
  }
  # Only execute run loop if exit hasn't been called
  #print STDERR "Willl exit for $$ : $will_exit  CV $CV\n";
  !$will_exit and $CV and $CV->recv;
}

sub _post_fork {

  cancel $tick_timer_raw;
  $tick_timer_raw=undef;
  $asap_timer=undef;
  %watchers=();
  %sig_watchers=();
  %uSAC::IO::procs=();
  $will_exit=undef;
  @asap=();
  @asap_args=();
  $STDERR->reset;
  $STDOUT->reset;


  #print STDERR "RESET AFTER FORK\n";

}

sub _exception{
  my $e=shift;
        use Error::Show;
        if($e=~/(\d+) RETURN/){
          ## NOTE SPECIAL EXCEPTION TO HANDLE CHILD FORK
          _post_fork();
          uSAC::IO::asay($STDERR, "IN ASAP EXCEPTION HANDLER $e");
          uSAC::Main::_do_it();
        }
        else {
          # NORMAL Execiption handling
          uSAC::IO::asay($STDERR, Error::Show::context $e);
        }
        return; 
}

1;
