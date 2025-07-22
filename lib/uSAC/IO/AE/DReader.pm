use Object::Pad;
package uSAC::IO::AE::DReader;
class uSAC::IO::AE::DReader :isa(uSAC::IO::DReader);
use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Errno qw(EAGAIN EINTR EINPROGRESS);
use Socket ":all";#qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in inet_aton>;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use constant::more DEBUG=>0;

field $_rw;
field $_reader;
#field $_rfh_ref;	#reference to parent

field $_fh;
field $_on_read; 
field $_on_eof;
field $_on_error;
field $_time;
field $_clock;

BUILD {
  #$_rfh_ref=\$self->fh;
}

#destroy io watcher, 
method pause :override {
	undef $_rw;
	$self;
}




method start :override ($fh=undef) {
  #$$_rfh_ref=$fh if $fh;
	$_rw= AE::io $_fh, 0, $_reader//=$self->_make_reader;
	$self;
}

#alias variables and create io watcher
method _make_reader :override {
  #\my $on_read=\$self->on_read; #alias cb 
  #\my $on_error=\$self->on_error;
	#\my $rw=\$self->[rw_];
	#\my $buf=\$self->[buffer_];
	\my $max_read_size=\$self->max_read_size;
  #\my $rfh=$_rfh_ref;#$self->rfh;		
  #\my $time=\$self->time;
  #\my $clock=\$self->clock;
	\my $flags=\$self->flags;

  my $_cb=sub {}; # Dummy for now

	$_rw=undef;
	sub {
		#$self->[time_]=$Time;	#Update the last access time
		$$_time=$$_clock;
		my $buf=[""];
		my $addr =IO::FD::recv($_fh, $buf->[0], $max_read_size, $flags);
		defined($addr) and return($_on_read and $_on_read->($buf, $addr, $_cb));
		($! == EAGAIN or $! == EINTR) and return;

    #warn "ERROR IN READER" if DEBUG;
		$_rw=undef;
		$_on_error->($!);
		return;
	};
}

method on_read :lvalue :override{
  $_on_read;
}

method on_error :lvalue :override{
  $_on_error;
}

method on_eof :lvalue :override {
  $_on_eof;
}

method time :lvalue :override {
  $_time;
}

method clock :lvalue :override {
  $_clock;
}

method fh :lvalue :override {
  $_fh;
}

1;
