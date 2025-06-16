use Object::Pad;
package uSAC::IO::SReader;
class uSAC::IO::SReader :isa(uSAC::IO::Reader);
use parent "uSAC::IO::Reader";
use uSAC::IO::Common;

#Class is used to auto detect which event system in use

my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::SReader");
eval "require $rb";

#Wrapper 
#sub sreader { shift; $rb->new(@_); }
#sub create { shift; $rb->new(fh=>@_); }
sub create {
  $rb->new(@_); }
1;


