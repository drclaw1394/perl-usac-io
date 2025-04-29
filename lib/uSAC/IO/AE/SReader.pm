
use Object::Pad;
package uSAC::IO::AE::SReader;
class uSAC::IO::AE::SReader :isa(uSAC::IO::SReader);
use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use uSAC::Log;
use Log::OK;

use IO::FD::DWIM();
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK :mode);

#use IO::FD::DWIM ":all";
#use IO::FD;

use Errno qw(EAGAIN EINTR);

field $_rw;
field $_reader;
		
field $_rfh_ref;

BUILD {
	$_rfh_ref=\$self->fh;
}

method start :override ($fh=undef) {

  if($fh){
    #my $res= IO::FD::fcntl $fh, F_SETFL, O_NONBLOCK;
	  $$_rfh_ref=$fh;
  }

  #reset buffer if new fh
  $self->buffer=[""] if $fh;
	$_rw= AE::io $$_rfh_ref, 0, $_reader//=$self->_make_reader;
  $uSAC::IO::AE::IO::watchers{$self}=$_rw;
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
	\my $on_error=\$self->on_error;
	#\my $rw=\$self->[rw_];
	\my $buf=\$self->buffer;
	\my $max_read_size=\$self->max_read_size;
	\my $rfh=$_rfh_ref;#$self->rfh;		
	\my $time=$self->time;
	\my $clock=$self->clock;
  \my $sysread=\$self->sysread;
	my $len;
  my $_cb=sub {}; # Dummy for now
	$_rw=undef;

	sub {
		$time=$clock;
    #$len = IO::FD::sysread($rfh, $buf, $max_read_size, length $buf );
		$len = $sysread->($rfh, $buf->[0], $max_read_size, length $buf->[0] );
		$len>0 and return($on_read and $on_read->($buf,$_cb));
		not defined($len) and ($! == EAGAIN or $! == EINTR) and return;

    # End of file
    $len==0 
      and (delete $uSAC::IO::AE::IO::watchers{$self}) 
      and (undef $_rw || 1)
		  and (($on_read and $on_read->($buf, undef)) ||1)
      and return($on_eof and $on_eof->($buf));

    # Error
		Log::OK::ERROR and log_error "ERROR IN READER: $!";
		$_rw=undef;
    delete $uSAC::IO::AE::IO::watchers{$self};
		$on_error and $on_error->(undef, $buf);
		return;
	};
}

#in the AE implementation, pause destroys the io watcher, which pauses the read
#events
method pause :override {
	undef $_rw;
  delete $uSAC::IO::AE::IO::watchers{$self};
	$self;
}

1;
