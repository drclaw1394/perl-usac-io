package uSAC::IO::AE::IO;

use strict;
use warnings;
#use v5.36;
use feature qw<try current_sub>;
no warnings "experimental";

#use Socket ":all";
#use Socket::More;
use Errno qw(EAGAIN EINTR EINPROGRESS);
#use parent "uSAC::IO";

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


my $CV;
my $will_exit;
my $tick_timer_raw;


sub _shutdown_loop {
  #print "SHUTDOWN LOOP CALLED\n";
  $CV and $CV->send;
}

sub _exit {
  # Do any cleanup before exiting 
  # Mark with will_exit to prevent blocking on undefined $CV
  $tick_timer_raw=undef;
  $will_exit=1;
  _shutdown_loop;
}


sub cancel ($){
  my $w=delete $watchers{$_[0]};
  $_[0]=undef; 
  #use Error::Show;
  #uSAC::IO::asay Error::Show::context undef;
}



# Processing sub for asap code refs.

my $asap_sub=sub {

  # Call subs with supplied arguments.
  #
  my $entry=shift @asap;
  my $args=shift @asap_args;
  try{
    $entry->(@$args);
  }
  catch($e){
    use Error::Show;
    print STDERR  " ____GOT EXCEPTION____ in pid $$: $e";#$;Error::Show::context message=>$e;
    if($e=~/(\d+) RETURN/){

      print STDERR  " START CHILD PROCESSING:";
       _post_fork();
       uSAC::Main::_do_it();
    }
    return; 
  }

  # Destroy the idle watcher/timer if nothing left to process!
  if(!@asap){
    $asap_timer=undef;

    delete $watchers{idle};
  }

};

# Schedule a code ref to execute asap on current event system.
#
sub asap (*@){
    my ($c, @args)=@_;
    if($c){
      # only push if a sub is given. Otherwise we just use as a way to restart the asap timer
      push @asap, $c;
      push @asap_args, \@args;
    }
    #uSAC::IO::asay $STDERR, "Restarting ASAP in $$ with ".@asap." args ";

    $asap_timer//=AE::idle $asap_sub;
    $watchers{idle}=$asap_timer;
    1;
}

sub timer ($$$){
    my ($offset, $repeat, $sub, $no_save)=@_;
    my $s="";
    my $id=\$s;
    $watchers{$id}=AE::timer $offset, $repeat, sub{
      delete $watchers{$id} unless($repeat);
      $sub->($id)
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
  $watchers{$pid}=AE::child $pid, sub {
    delete $watchers{$_[0]};
    &$sub;
  }
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
	my $res=IO::FD::connect IO::FD::DWIM::fileno($socket), $addr;
  unless($res){
    #EAGAIN for pipes
    if($! == EAGAIN or $! == EINPROGRESS){
      my $cw;$cw=AE::io $socket, 1, sub {
              #Need to check if the socket has
              my $sockaddr=IO::FD::getpeername $socket;

              delete $watchers{$id};

              if($sockaddr){
                      uSAC::IO::asay "IN socket connect callback: ";
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
      $on_error and asap $on_error, $socket, "$!";
    }
    return;
  }
  # Syncrhonous connect. reshedual
  asap $on_connect, $socket, $addr if $on_connect;

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
  uSAC::IO::asay $STDERR, "CALLING PRE LOOP $$\n";
  $will_exit=undef;
  # Create a cv; 
  $CV=AE::cv unless $CV;
  return;
}

sub _post_loop {
  uSAC::IO::asay $STDERR, "CALLING POST LOOP $$\n";
  # Create a tick timer, which isn't part of the normal watcher list
  # When no watchers are present, 
  unless($tick_timer_raw){
    $tick_timer_raw=1; # Synchronous true until asap is called
    asap sub {
      my $id=timer 0, 0.1, sub {
        $uSAC::IO::Clock=time;
        #print STDERR "WATCHERS for $$ ARE ". join " ", %watchers;
        #print STDERR "\n";
        _exit unless %watchers;
      };

      $tick_timer_raw=delete $watchers{$id};
    };
  }
  # Only execute run loop if exit hasn't been called
  print STDERR "Willl exit for $$ : $will_exit\n";
  uSAC::IO::asay $STDERR, "CV for $$ is $CV\n";
  !$will_exit and $CV and $CV->recv;
}

sub _post_fork {

  print STDERR "POST FORK $$ ====\n";
  %watchers=();
  %sig_watchers=();
  $asap_timer=undef;
  $CV->send();
  $CV=undef;
  #$tick_timer_raw=undef;
  #$will_exit=undef;
  #$CV=undef;

  print STDERR "RESET AFTER FORK\n";

}


1;
