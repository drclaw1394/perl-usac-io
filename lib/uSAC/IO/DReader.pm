use Object::Pad;
package uSAC::IO::DReader;
class uSAC::IO::DReader :isa(uSAC::IO::Reader);
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use Errno qw(EAGAIN EINTR);
use Data::Dumper;

use uSAC::IO::Common;

use constant DEBUG=>0;

my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::DReader");
say $rb;
unless(eval "require $rb"){
	say "ERROR IN REQUIRE";
	say $@;
}

field $_flags :mutator;

sub dreader { shift; $rb->new(@_); }

1;
