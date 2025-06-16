
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
  $uSAC::IO::AE::IO::watchers{$self}=$_rw;

	$self;
}

method _make_reader  :override {
#alias variables and create io watcher
	
  my $on_read;
	#NOTE: Object::Pad does not allow child classes to have access to 
	#parent fields. Here we alias what we need so 'runtime' access is
	#not impacted
	#
	#\my $rw=\$self->[rw_];
	my $buf=$self->buffer;
	my $max_read_size=$self->max_read_size;
	my $rfh=$self->fh;
	my $time=$self->time;
	my $clock=$self->clock;
  my $sysread=$self->sysread;
	my $len;
  my $_cb=sub {}; # Dummy for now
	$_rw=undef;

	sub {

	  $on_read//=$self->on_read; 
		$$time=$$clock;
		$len = $sysread->($rfh, $buf->[0], $max_read_size, length $buf->[0] );
		$len>0 and return($on_read and $on_read->($buf,$_cb));
		not defined($len) and ($! == EAGAIN or $! == EINTR) and return;

    # End of file
    if($len==0){
      delete $uSAC::IO::AE::IO::watchers{$self};
      undef $_rw;
      #$on_read and $on_read->($buf, undef);
      my $on_eof=$self->on_eof;
      $on_eof and $on_eof->($buf);
    }
    # Error
		Log::OK::ERROR and log_error "ERROR IN READER: $!";
		$_rw=undef;
    delete $uSAC::IO::AE::IO::watchers{$self};
    my $on_error=$self->on_error;
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

method destroy :override {
  Log::OK::TRACE and log_trace "--------DESTROY  in AE::SReader\n";
  $self->SUPER::destroy();
  $_rw=undef;
  $_reader=undef;

}

1;
