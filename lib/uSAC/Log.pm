package uSAC::Log;
use strict;
use warnings;
no warnings "experimental";
use Export::These qw<
  usac_log_trace
  usac_log_debug
  usac_log_warn
  usac_log_info
  usac_log_error
  usac_log_fatal
>;

#  Send via broker
use uSAC::FastPack::Broker;

sub usac_log_trace {
  unshift @_, undef, "usac/log/trace"; 
  &$uSAC::Main::broadcaster;
}

sub usac_log_debug {
  unshift @_, undef, "usac/log/debug"; 
  &$uSAC::Main::broadcaster;
}

sub usac_log_warn {
  unshift @_, undef, "usac/log/warn"; 
  &$uSAC::Main::broadcaster;
}
sub usac_log_info {
  unshift @_, undef, "usac/log/info"; 
  &$uSAC::Main::broadcaster;
}

sub usac_log_error {
  print "IN ERRROR \n";
  &$uSAC::Main::broadcaster;
}

sub usac_log_fatal {
  unshift @_, undef, "usac/log/fatal"; 
  &$uSAC::Main::broadcaster;
}


1;
