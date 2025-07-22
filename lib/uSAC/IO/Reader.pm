use Object::Pad;
package uSAC::IO::Reader;
class uSAC::IO::Reader;

use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;

#use AnyEvent;
use uSAC::Log;
use Log::OK;

use Errno qw(EAGAIN EINTR);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use IO::FD;

#pass in fh, ctx, on_read, on_eof, on_error
#Returns a method which is called with a buffer, an optional callback and argument

field $_ctx;
field $_fh :param;
#field $_reader 	:mutator;
#
#field $_time	:mutator :param = undef;
#field $_clock	 :mutator :param = undef;
#field $_on_read :mutator :param = undef;
#field $_on_eof  :mutator :param = undef;
#field $_on_error :mutator :param = undef;
#
field $_max_read_size :mutator :param = undef;
field $_buffer	:mutator;
field $_sysread :mutator :param =undef;
		
	
BUILD{
	$_fh=fileno($_fh) if ref($_fh);	#Ensure we are working with a fd
  $self->fh=$_fh;
	IO::FD::fcntl $_fh, F_SETFL, O_NONBLOCK;

	$self->on_read=sub {$self->pause};
	$self->on_error= $self->on_eof=sub{};

	$_max_read_size//=4096*4;
	$_buffer=[IO::FD::SV($_max_read_size)];#"";
  $_sysread//=\&IO::FD::sysread;

	
  my $time=time;
  my $clock=time;
  #my $time=0;
  $self->time=\$time;
  $self->clock=\$clock;
}

method on_read {
  # needs override
}

method on_error {

}

method on_eof {
}

method time {
}

method clock {
}

# Accessor API
#
#Set the external variables to use as clock source and timer
method timing {
	($self->time, $self->clock)=@_;
}

method fh {

}



#manually call on_read if buffer is not empty
method pump {
	self->on_read->($_buffer, undef); # if $_buffer;
}

method read {
	my $size=$_[1]//4096*4;
	#force a manual read into buffer
  $_sysread->($self->fh, $size, $_buffer);
	$self->on_read->($_buffer, undef) if $_buffer;
}


method start {
	#method class for backend to override
}

method pause{
	#method class for backend to override
}

method _make_reader {

}

method pipe_to ($writer, $limit=undef){
	my $counter;
	\my @queue=$writer->queue;
	$self->on_read= sub {
    #my $data=$_[0][0];	#Copy data
    #$_[0][0]="";	#Consume input
		if(!$limit  or $#queue < $limit){
			#The next write cannot equal the limit so blaze ahead
			#with no callback,
      #$writer->write($data);
			$writer->write($_[0]);
		}
		else{
			#the next write will equal the limit,
			#use a callback
			$self->pause;	#Pause the reader
      #$writer->write($data, sub{
			$writer->write($_[0], sub{
				#restart the reader
				$self->start;
			});
		}
		$_[0][0]="";	#Consume input
	};
  $self->start;
	$writer; #Return writer to allow chaining
}


method destroy {
  Log::OK::TRACE and log_trace "--------DESTROY  in Reader\n";
  $self->on_read=undef;
  $self->on_eof=undef;
  $self->on_error=undef;
}

1;

__END__

=head1 NAME

uSAC::IO::Reader

=head1 SYNOPSIS

	use uSAC::IO;
	my $reader= uSAC::IO->reader(fileno $fh);
  # $reader will automaticall be a stream or datagram reader
	
=head1 DESCRIPTION

Main interface for creating a reader object for a file descriptor.  It is a
parent class to implementation specific readers. As such it isn't intended to
be instancated directly, but rather using the wrapper.



=head1 API

=head2  timing

	timing( $time, $clock)

Calling this method with two references to scalars to use as the time and clock
for the reader. When a read event is processed by the reader, the C<$clock> is
derefernced and the value stored into the dereferenced C<$time> variable.

This isolates any timeout logic to outside the reader for optimal performance
and flexibility

=head2 pump
	
	$reader->pump

Manually triggers the processing of data in the reader


=head2 read
	
	$reader->read($size)

Manually read C<$size> bytes from reader. executes the on_read callback if
buffer becomes non empty

This really should only be used in limited scenarious where there an event loop
might not be available. ie testing

=head2 start

	$reader->start

After a reader has been created, it needs to be started to handle read events


=head2 pause 

	$reader->pause

Stops a reader for processing any further read events.


=head2 pipe_to

	$reader->pipe_to($writer)

Provides an easy way to link a reader to a writer object. Automatically starts the reader
