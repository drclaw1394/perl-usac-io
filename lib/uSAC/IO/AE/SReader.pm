
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

field $_on_read :param = undef; 
field $_on_eof :param = undef;
field $_on_error :param = undef;
field $_time :param = undef;
field $_clock :param = undef;
field $_fh;
field $_buffer;#	:mutator;
field $_id;
field $_on_can_read :param = undef;

		

BUILD {

  $_id="$self";
}

method start :override ($fh=undef) {
  if($fh){
    #my $res= IO::FD::fcntl $fh, F_SETFL, O_NONBLOCK;
    $self->fh=$fh;

    #reset buffer if new fh
    $_buffer=[""];

    $_reader=undef;
    if($_on_can_read){
      # only report the descripter is readable
      $_reader=$self->_make_can_read;
    }
    else {

      $_reader=$self->_make_reader;
    }
    $_rw= AE::io $fh, 0, $_reader;
  }
  else{
    # Reuse existing reader
    unless($_reader){
      if($_on_can_read){
        $_reader=$self->_make_can_read;
      }
      else{
        $_reader=$self->_make_reader;
      }
    }
    $_rw= AE::io $self->fh, 0, $_reader;
  }

  # Refresh the local copy of on read
  #$uSAC::IO::AE::IO::watchers{$self}=$_rw;
  $uSAC::IO::AE::IO::watchers{$_id}=$_rw;

	$self;
}

method _make_can_read {
    sub {
      use feature "try";
      try {
        $_on_can_read and $_on_can_read->();
      }
      catch($e){
        uSAC::IO::AE::IO::_exception($e);
      }
    }
}

method _make_reader  :override {
#alias variables and create io watcher
	
  #my $on_eof;
	#NOTE: Object::Pad does not allow child classes to have access to 
	#parent fields. Here we alias what we need so 'runtime' access is
	#not impacted
	#
	my $max_read_size=$self->max_read_size;
  my $sysread=$self->sysread;
	my $len;
  my $_cb=sub {}; # Dummy for now
	$_rw=undef;

	sub {
    use feature "try";
    try {
    #$_on_eof//=$self->on_eof;
		$$_time=$$_clock;
		$len = $sysread->($_fh, $_buffer->[0], $max_read_size, length $_buffer->[0] );
		$len>0 and return($_on_read and $_on_read->($_buffer,$_cb));
		not defined($len) and ($! == EAGAIN or $! == EINTR) and return;

    # End of file
    if($len==0){
      #delete $uSAC::IO::AE::IO::watchers{$self};
      delete $uSAC::IO::AE::IO::watchers{$_id};
      undef $_rw;
      $_on_eof and $_on_eof->($_buffer);
    }
    # Error
    #Log::OK::ERROR and log_error "ERROR IN READER: $!";
		$_rw=undef;
    #delete $uSAC::IO::AE::IO::watchers{$self};
    delete $uSAC::IO::AE::IO::watchers{$_id};
    #my $_on_error=$self->on_error;
		$_on_error and $_on_error->(undef, $_buffer);
		return;
  }
  catch($e){
    uSAC::IO::AE::IO::_exception($e);
  }
	};
}

#in the AE implementation, pause destroys the io watcher, which pauses the read
#events
method pause :override {
	undef $_rw;
  #delete $uSAC::IO::AE::IO::watchers{$self};
  delete $uSAC::IO::AE::IO::watchers{$_id};
  #$_reader=undef;
	$self;
}

method destroy :override {
  Log::OK::TRACE and log_trace "--------DESTROY  in AE::SReader\n";
  $self->SUPER::destroy();
  delete $uSAC::IO::AE::IO::watchers{$_id};
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

method on_can_read :lvalue :override{
  $_on_can_read;
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
method buffer :lvalue :override {
  $_buffer;
}

1;
