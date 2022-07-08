use Object::Pad;
package uSAC::IO::DWriter;
class uSAC::IO::DWriter :isa(uSAC::IO::Writer);
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use Errno qw(EAGAIN EINTR);
use uSAC::IO::Common;


my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::DWriter");
#say $rb;
unless(eval "require $rb"){
	#say "ERROR IN REQUIRE";
	#die "Counld not load backend $rb: $@";
	#say $@;
}


sub dwriter { shift; $rb->new(@_); }

1;
