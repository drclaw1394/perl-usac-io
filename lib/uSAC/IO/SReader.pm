package uSAC::IO::SReader;
use strict;
use warnings;
use feature "say";
use parent "uSAC::IO::Reader";
use uSAC::IO::Common;

#Class is used to auto detect which event system in use

my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::SReader");
eval "require $rb";
#############################################
# #say $sb;                                 #
# {                                         #
#         no strict qw<refs>;               #
#         *_inet=*{"$rb"."::connect_inet"}; #
# }                                         #
#############################################

#Wrapper 
sub new {
	my $package=shift;
	if ($package eq __PACKAGE__){
		#caller user application
		$rb->new(@_);
	}
	else{
		#called by child class
		$package->SUPER::new(@_);
	}
}
1;


