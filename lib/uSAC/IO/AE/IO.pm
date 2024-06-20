package uSAC::IO::AE::IO;

use strict;
use warnings;
#use v5.36;
use feature qw<say try current_sub>;
no warnings "experimental";

#use Socket ":all";
#use Socket::More;
use Errno qw(EAGAIN EINTR EINPROGRESS);
#use parent "uSAC::IO";

use AnyEvent;
use IO::FD;


# Postpone a subroutine call
my @asap;
my @asap_args;
my $asap_timer;
my $entry;


my $CV;
# Code to setup event loop before it starts
sub _pre_loop {
  #print "CALLING PRE LOOP\n";
  # Create a cv; 
  $CV=AE::cv;
  return;
}

sub _post_loop {
  #print "POST LOOP CALLED\n";
  $CV->recv;
}

sub _shutdown_loop {
  #print "SHUTDOWN LOOP CALLED\n";
  $CV->send;
}

sub _exit {
  # Do any cleanup before exiting 
  _shutdown_loop;
}





# Processing sub for asap code refs. Supports recursive asap calls.
my $asap_sub=sub {
                        
  # Call subs with supplied arguments.
  my $entry;
  my $args;
  while($entry=shift @asap){
    #print "ASAP WHILE LOOP\n";
    $args=shift @asap_args;
    try{
      $entry->(@$args);
    }
    catch($e){
        warn "Uncaught execption in asap callback: $e";
    }
  }
  $asap_timer=undef; 
};

# Schedule a code ref to execute asap on current event system.
# currently a shared timer.
#
sub asap (*@){
    my ($c, @args)=@_;
    push @asap, $c;
    push @asap_args, \@args;
    $asap_timer//=AE::timer 0, 0, $asap_sub;
    1;
}

my %timer;
my $timer_id=1;  #Start at a true value
sub timer ($$$){
    my ($offset, $repeat, $sub)=@_;
    my $id=$timer_id++;
    $timer{$id}=AE::timer $offset, $repeat, sub{$sub->($id)};
    $id;
}

sub timer_cancel ($){
  delete $timer{$_[0]};
  $_[0]=undef; 
}

my %signal;
my $signal_id=1;
sub signal ($$){
  my ($name, $sub)=@_;
  my $id=$signal_id++;
  $signal{$id}=AE::signal $name, sub { $sub->($id)};
  $id;
}

sub signal_cancel ($){
  delete $signal{$_[0]};
  $_[0]=undef; 
}





my %watchers;
my $id;
sub connect_addr {
  #A EINPROGRESS is expected due to non block
  my ($socket, $addr, $on_connect, $on_error)=@_;

	$id++;
	my $res=IO::FD::connect $socket, $addr;
  unless($res){
    #EAGAIN for pipes
    if($! == EAGAIN or $! == EINPROGRESS){
      my $cw;$cw=AE::io $socket, 1, sub {
              #Need to check if the socket has
              my $sockaddr=IO::FD::getpeername $socket;

              delete $watchers{$id};

              if($sockaddr){
                      $on_connect->($socket, $addr) if $on_connect;
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
      #say 'Synchronous fail';
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

sub accept {

}

sub cancel_accept {

}


1;
