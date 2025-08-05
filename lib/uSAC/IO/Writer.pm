use Object::Pad;
class uSAC::IO::Writer;
use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;

use IO::FD;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use uSAC::Log;
use Log::OK;
use Errno qw(EAGAIN EINTR);

field $_ctx;
field $_fh :param :mutator;
field $_time :mutator :param = undef;
field $_clock :mutator :param = undef;
#field $_on_drain :mutator :param =undef;
#field $_on_eof   :mutator :param =undef;
#field $_on_error :mutator :param =undef;
field $_writer;
field $_resetter;
field @_queue; 
field $_syswrite :mutator :param = undef;
field $_time_dummy;

BUILD {
	$_fh=fileno($_fh) if ref($_fh);	#Ensure we are working with a fd
	IO::FD::fcntl($_fh, F_SETFL, O_NONBLOCK);
  #$_on_drain//=$_on_error//=sub{};
	$self->on_drain//=$self->on_error//=sub{};
  $_syswrite//=\&IO::FD::syswrite;
	#$self->[writer_]=undef;
	#@_queue;
  
  unless(ref $_time){
    # Link to dummy time variable is none provided
    $_time_dummy=time;
    $_time=\$_time_dummy;
  }

  unless(ref $_clock){
    # always need  a clock
    $_clock=\$uSAC::IO::Clock;
  }

}

ADJUST {
	#make a writer
  $self->set_write_handle($_fh);

}

method on_error  {
}
method on_eof  {
}

method on_drain  {
}

method timing {
	($_time, $_clock)=@_;
}

#return or create an return writer
method writer {
  #$_writer//=$self->_make_writer;
}

method reset {
}

#OO interface
method write {
}



###############################
# method on_eof : lvalue {    #
#         $_[0][on_eof_]->$*; #
# }                           #
###############################




#SUB CLASS SPECIFIC
#
method pause {

}

method set_write_handle {

}

method _make_writer {
}

method _make_reseter {

}

method queue {
	\@_queue;
}

method destroy {
  Log::OK::TRACE and log_trace "--------DESTROY  in Writer\n";
  #$_on_drain=undef;
  $self->on_drain=undef;
  #$_on_eof=undef;
  $self->on_eof=undef;
  #$_on_error=undef;
  $self->on_error=undef;
  for(@_queue){
    $_->[2]=undef;
  }
  @_queue=();
  $_syswrite=undef;
  $_time_dummy=undef;
}
1;

__END__

=head1 NAME

uSAC::IO::Writer

=head1 SYNOPSIS
	use uSAC::IO;
	my $writer= uSAC::IO->writer(fileno $fh);
	
=head1 DESCRIPTION

Main interface for creating a writer object for a file descriptor.  It is a
parent class to implementation specific writers. As such it isn't intended to
be instancated directly, but rather using the wrapper.





=head1 API

=head2 Methods
=head3  timing

	$writer->timing($time, $clock);

Calling this method with two references to scalars to use as the time and clock
for the reader. When a write event is processed by the writer, the C<$clock> is
derefernced and the value stored into the dereferenced C<$time> variable.

This isolates any timeout logic to outside the reader for optimal performance
and flexibility


=head3 writer

	$writer->writer;

Returns the underlying subroutine ref which performs the writing operation. Creates it if non existant

=head3 write

	$writer->write($data, $cb)

Calls the underlying subroutine ref which performs the writing operation

=head3 pause

	$writer->pause;

Pause the internal queue from processing anymore data. Automatically unpauses on next call to C<write>

=head3 set_write_handle

	$writer->set_write_handle($handle)

Sets the handle the writer will operate on

=head2 Accessors

=head3 on_drain

	$writer->on_drain=sub{...}

lvalue access to the on_drain sub routine callback.

=head3 queue

	$writer->queue;

Returns a reference to internal queue..

