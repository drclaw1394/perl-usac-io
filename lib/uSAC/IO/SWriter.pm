use Object::Pad;
package uSAC::IO::SWriter;
class uSAC::IO::SWriter :isa(uSAC::IO::Writer);

use uSAC::IO::Common;

#Class is used to auto detect which event system in use

my $backend=uSAC::IO::Common::detect_backend;

my $sb=($backend."::SWriter");
eval "require $sb";

my $wb=($backend."::SWriter");
eval "require $wb";


#Wrapper class method calling backend
sub swriter{ shift; $wb->new(@_); }
1;


