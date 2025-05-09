use Object::Pad;
package uSAC::IO::DReader;
class uSAC::IO::DReader :isa(uSAC::IO::Reader);

use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;

use Errno qw(EAGAIN EINTR);

use uSAC::IO::Common;

use constant::more DEBUG=>0;

my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::DReader");
die "Could not require $rb" unless(eval "require $rb");

field $_flags :mutator;

#sub dreader { shift; $rb->new(@_); }
#sub create { shift; $rb->new(fh=>@_); }
sub create {$rb->new(@_); }

1;
