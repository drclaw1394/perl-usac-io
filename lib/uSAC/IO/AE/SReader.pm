
use Object::Pad;
package uSAC::IO::AE::SReader;
class uSAC::IO::AE::SReader :isa(uSAC::IO::SReader);
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Log::ger;
use Log::OK;
#use IO::FD::DWIM ":all";
use IO::FD;

use Errno qw(EAGAIN EINTR);
use Data::Dumper;

field $_rw;
field $_reader;
		
field $_rfh_ref;

BUILD {
	$_rfh_ref=\$self->fh;
}

method start :override ($fh=undef) {
	$$_rfh_ref=$fh if $fh;
	$_rw= AE::io $$_rfh_ref, 0, $_reader//=$self->_make_reader;
	$self;
}

method _make_reader  :override {
#alias variables and create io watcher
	
	#NOTE: Object::Pad does not allow child classes to have access to 
	#parent fields. Here we alias what we need so 'runtime' access is
	#not impacted
	#
	\my $on_read=\$self->on_read; #alias cb 
	\my $on_eof=\$self->on_eof;
	#say $self->on_eof;
	\my $on_error=\$self->on_error;
	#\my $rw=\$self->[rw_];
	\my $buf=\$self->buffer;
	\my $max_read_size=\$self->max_read_size;
	\my $rfh=$_rfh_ref;#$self->rfh;		
	\my $time=$self->time;
	\my $clock=$self->clock;
	my $len;
	$_rw=undef;
	sub {
		$time=$clock;
		$len = IO::FD::sysread($rfh, $buf, $max_read_size, length $buf );
		$len>0 and return($on_read and $on_read->($buf));
		$len==0 and return($on_eof and $on_eof->($buf));
		($! == EAGAIN or $! == EINTR) and return;

		Log::OK::ERROR and log_error "ERROR IN READER: $!";
		$_rw=undef;
		$on_error->(undef, $buf);
		return;
	};
}

#in the AE implementation, pause destroys the io watcher, which pauses the read
#events
method pause :override {
	undef $_rw;
	$self;
}

1;
