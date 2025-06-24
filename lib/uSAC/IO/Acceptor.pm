use Object::Pad;
package uSAC::IO::Acceptor;
use uSAC::IO::Common;
use IO::FD;

use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);


class uSAC::IO::Acceptor;




field $_fh :param :mutator;
field $_on_accept :param :mutator;
field $_on_error :param :mutator;
		
	
BUILD{
	$_fh=fileno $_fh if ref($_fh);	#Ensure we are working with a fd
	die "Could not set NON BLOCKING mode for fd" unless defined IO::FD::fcntl $_fh, F_SETFL, O_NONBLOCK;


	$_on_accept//=sub {$self->pause};
	$_on_error//=sub{$self->pause};

}


method start {
	#method class for backend to override
}

method _make_acceptor {

}

method pause{
	#method class for backend to override
}


my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::Acceptor");

die "Could not require $rb" unless(eval "require $rb");
#Wrapper 
sub create { shift; $rb->new(@_); }
1;

__END__

