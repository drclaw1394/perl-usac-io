use Object::Pad;
package uSAC::IO::DWriter;
class uSAC::IO::DWriter :isa(uSAC::IO::Writer);
use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;

use Errno qw(EAGAIN EINTR);
use uSAC::IO::Common;


my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::DWriter");
die "Could not require $rb" unless(eval "require $rb");


#sub dwriter { shift; $rb->new(@_); }
#sub create { shift; $rb->new(fh=>@_); }
sub create {$rb->new(@_); }

1;
