use Object::Pad;
class uSAC::IO::Writer;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use IO::FD;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use Log::ger;
use Log::OK;
use Errno qw(EAGAIN EINTR);

field $_ctx;
field $_fh :param :mutator;
field $_time :param :mutator;
field $_clock :param :mutator;
field $_on_drain;
field $_on_eof;
field $_on_error :param :mutator;
field $_writer;
field $_resetter;
field @_queue; 
field $_syswrite :param :mutator;

BUILD {
	$_fh=fileno $_fh if ref($_fh);	#Ensure we are working with a fd
	IO::FD::fcntl $_fh, F_SETFL, O_NONBLOCK;
	$_on_drain//=$_on_error//=sub{};
  $_syswrite//=\&IO::FD::syswrite;
	#$self->[writer_]=undef;
	#@_queue;
  
  #my $time=0;

  #$_time=\$time;
  #$_clock=\$time;

}

ADJUST {
	#make a writer
	$_writer=$self->_make_writer;

}
method timing {
	($_time, $_clock)=@_;
}

#return or create an return writer
method writer {
	$_writer//=$self->_make_writer;
}

method reset {
  $_resetter//=$self->_make_reseter;
}

#OO interface
method write {
	&{$_writer};
}



###############################
# method on_eof : lvalue {    #
#         $_[0][on_eof_]->$*; #
# }                           #
###############################


method on_drain : lvalue{
	$_on_drain;
}


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

