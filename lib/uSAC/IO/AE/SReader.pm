
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

field $_on_read; 
field $_on_eof;
field $_on_error;
field $_time;
field $_clock;
field $_fh;

		
#field $_rfh;

BUILD {
  #$_rfh=$self->fh;
}

method start :override ($fh=undef) {
  if($fh){
    #my $res= IO::FD::fcntl $fh, F_SETFL, O_NONBLOCK;
    $self->fh=$fh;

    #reset buffer if new fh
    $self->buffer=[""];

    $_reader=undef;
    $_reader=$self->_make_reader;
    $_rw= AE::io $fh, 0, $_reader;
  }
  else{
    # Reuse existing reader
    $_reader//=$self->_make_reader;
    $_rw= AE::io $self->fh, 0, $_reader;
  }

  # Refresh the local copy of on read
  #$_on_read=$self->on_read; 
  #$_on_eof=$self->on_eof;
  $uSAC::IO::AE::IO::watchers{$self}=$_rw;

	$self;
}

method _make_reader  :override {
#alias variables and create io watcher
	
  #my $on_read;
  #my $on_eof;
	#NOTE: Object::Pad does not allow child classes to have access to 
	#parent fields. Here we alias what we need so 'runtime' access is
	#not impacted
	#
	#\my $rw=\$self->[rw_];
	my $buf=$self->buffer;
	my $max_read_size=$self->max_read_size;
	my $rfh=$self->fh;
  #my $time=$self->time;
  #my $clock=$self->clock;
  my $sysread=$self->sysread;
	my $len;
  my $_cb=sub {}; # Dummy for now
	$_rw=undef;

	sub {

    #$_on_read//=$self->on_read; 
    #$_on_eof//=$self->on_eof;
		$$_time=$$_clock;
		$len = $sysread->($rfh, $buf->[0], $max_read_size, length $buf->[0] );
		$len>0 and return($_on_read and $_on_read->($buf,$_cb));
		not defined($len) and ($! == EAGAIN or $! == EINTR) and return;

    # End of file
    if($len==0){
      delete $uSAC::IO::AE::IO::watchers{$self};
      undef $_rw;
      $_on_eof and $_on_eof->($buf);
    }
    # Error
    #Log::OK::ERROR and log_error "ERROR IN READER: $!";
		$_rw=undef;
    delete $uSAC::IO::AE::IO::watchers{$self};
    #my $_on_error=$self->on_error;
		$_on_error and $_on_error->(undef, $buf);
		return;
	};
}

#in the AE implementation, pause destroys the io watcher, which pauses the read
#events
method pause :override {
	undef $_rw;
  delete $uSAC::IO::AE::IO::watchers{$self};
  $_reader=undef;
	$self;
}

method destroy :override {
  Log::OK::TRACE and log_trace "--------DESTROY  in AE::SReader\n";
  $self->SUPER::destroy();
  $_rw=undef;
  $_reader=undef;

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
