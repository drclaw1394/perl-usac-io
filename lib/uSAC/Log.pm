package uSAC::Log::ger;
# Log::ger does not have the required symbols internally. They are
# synthectically generated in target pacakges.. so here we give it a target
# with a decoy package. This prevents our symbols from colliding

use Log::ger;



package uSAC::Log;

our $VERSION=v0.1.0;

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

use constant::more DEBUG=>-0;

my $use_usac=1;

BEGIN { $use_usac=%uSAC::Main:: }

# TODO map symbols directly so not to use conditional statements

sub log_trace {
  if($use_usac){
    DEBUG and print STDERR "log with usac\n";
    unshift @_, undef, "usac/log/trace"; 
    &$uSAC::Main::broadcaster;
  }
  else {
    DEBUG and print STDERR "log with Log::ger\n"; 
    &uSAC::Log::ger::log_trace;
  }
}

sub log_debug {
  if($use_usac){
    unshift @_, undef, "usac/log/debug"; 
    &$uSAC::Main::broadcaster;
  }
  else {
    &uSAC::Log::ger::log_debug;
  }
}

sub log_warn {
  if($use_usac){
    unshift @_, undef, "usac/log/warn"; 
    &$uSAC::Main::broadcaster;
  }
  else {
    &uSAC::Log::ger::log_warn;
  }
}
sub log_info {
  if($use_usac){
    unshift @_, undef, "usac/log/info"; 
    &$uSAC::Main::broadcaster;
  }
  else {
    &uSAC::Log::ger::log_info;
  }
}

sub log_error {
  if($use_usac){
    unshift @_, undef, "usac/log/error"; 
    &$uSAC::Main::broadcaster;
  }
  else {
    &uSAC::Log::ger::log_error;
  }
}

sub log_fatal {
  if($use_usac){
    unshift @_, undef, "usac/log/fatal"; 
    &$uSAC::Main::broadcaster;
  }
  else {
    &uSAC::Log::ger::log_fatal;
  }
}

1;

=head1 TITLE

uSAC::Log - Wrapper for synch/ asynch logging

=head1 SYNOPSIS

  use uSAC::Log;

  

=head1 DESCRIPTION

A shim pacakge to allow both synchrounus logging using L<Log::ger> and
asynchronous logging (when implemented ) in the upcoming uSAC distribution.

If you don't know what any of those things are, do don't need this package !

Primarily this would only be used if you intend to make a distri


=head1 AUTHOR

Ruben Westerberg, E<lt>drclaw@mac.comE<gt>

=head1 REPOSITORTY and BUGS

Please report any bugs via git hub: L<http://github.com/drclaw1394/perl-usac-log>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2025 by Ruben Westerberg

Licensed under MIT

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE.

=cut

