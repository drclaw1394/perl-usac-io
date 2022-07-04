package uSAC::IO::DReader;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use Errno qw(EAGAIN EINTR);
use Data::Dumper;

use parent "uSAC::IO::Reader";
#use uSAC::IO::Reader qw<:fields>;	#Import field names

use Exporter "import";
use uSAC::IO::Common;

use constant DEBUG=>0;

my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::DReader");
say $rb;
unless(eval "require $rb"){
	say "ERROR IN REQUIRE";
	say $@;
}
else
{
        #######################################
        # no strict qw<refs>;                 #
        # *connect=*{"$rb"."::connect_inet"}; #
        # *bind=*{"$rb"."::bind_inet"};       #
        #######################################
}

use constant KEY_OFFSET=>uSAC::IO::Reader::KEY_OFFSET+uSAC::IO::Reader::KEY_COUNT;

use enum ("flags_=".KEY_OFFSET, qw<>);

use constant KEY_COUNT=>flags_-flags_+1;
my @fields=qw<flags_>;

our @EXPORT_OK=@fields;
our %EXPORT_TAGS=("fields"=>\@fields);

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




sub flags : lvalue{
	$_[0][flags_];
}
1;
