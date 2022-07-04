package uSAC::IO::DWriter;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Errno qw(EAGAIN EINTR);
use constant DEBUG=>0;

use parent "uSAC::IO::Writer";
use Exporter "import";
use uSAC::IO::Common;

use constant KEY_OFFSET=>uSAC::IO::Writer::KEY_OFFSET+uSAC::IO::Writer::KEY_COUNT;
use constant KEY_COUNT=>0;

my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::DWriter");
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
