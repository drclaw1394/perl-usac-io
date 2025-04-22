package uSAC::Log;
use strict;
use warnings;
no warnings "experimental";
use Export::These qw<
  log_trace
  log_debug
  log_warn
  log_info
  log_error
  log_fatal
>;

#  Send via broker
#use uSAC::FastPack::Broker;

sub log_trace {
  unshift @_, undef, "usac/log/trace"; 
  &$uSAC::Main::broadcaster;
}

sub log_debug {
  unshift @_, undef, "usac/log/debug"; 
  &$uSAC::Main::broadcaster;
}

sub log_warn {
  unshift @_, undef, "usac/log/warn"; 
  &$uSAC::Main::broadcaster;
}
sub log_info {
  unshift @_, undef, "usac/log/info"; 
  &$uSAC::Main::broadcaster;
}

sub log_error {
  unshift @_, undef, "usac/log/error"; 
  &$uSAC::Main::broadcaster;
}

sub log_fatal {
  unshift @_, undef, "usac/log/fatal"; 
  &$uSAC::Main::broadcaster;
}


1;
