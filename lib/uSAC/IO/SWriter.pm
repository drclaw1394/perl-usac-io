package uSAC::IO::SWriter;
use strict;
use warnings;
use parent "uSAC::IO::Writer";
use uSAC::IO::Common;

#Class is used to auto detect which event system in use

my $backend=uSAC::IO::Common::detect_backend;

my $sb=($backend."::SWriter");
eval "require $sb";
#############################################
# #say $sb;                                 #
# {                                         #
#         no strict qw<refs>;               #
#         *_inet=*{"$sb"."::connect_inet"}; #
# }                                         #
#############################################

my $wb=($backend."::SWriter");
eval "require $wb";


#Wrapper 
sub new {
	my $package=shift;
	$wb->new(@_);
}
1;


