use Object::Pad;
package uSAC::IO::Reader;
class uSAC::IO::Reader;

use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

#use AnyEvent;
use Log::ger;
use Log::OK;

use Errno qw(EAGAIN EINTR);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Data::Dumper;
use Exporter "import";

#use IO::FD::DWIM ":all";
use IO::FD;

#pass in fh, ctx, on_read, on_eof, on_error
#Returns a method which is called with a buffer, an optional callback and argument

field $_ctx;
field $_fh :param :mutator;
field $_reader 	:mutator;
field $_time	:param :mutator;
field $_clock	 :param :mutator;
field $_on_read :param :mutator;
field $_on_eof  :param :mutator;
field $_on_error :param :mutator;
field $_max_read_size :param :mutator;
field $_buffer	:mutator;
		
	
BUILD{
	$_fh=fileno $_fh if ref($_fh);	#Ensure we are working with a fd
	IO::FD::fcntl $_fh, F_SETFL, O_NONBLOCK;

	$_on_read//=sub {$self->pause};
	$_on_error//= $_on_eof//=sub{};

	$_max_read_size//=4096;
	$_buffer=IO::FD::SV($_max_read_size);#"";

	
  #my $time=0;
  #$_time=\$time;
  #$_clock=\$time;
}


# Accessor API
#
#Set the external variables to use as clock source and timer
method timing {
	($_time, $_clock)=@_;
}



#manually call on_read if buffer is not empty
method pump {
	$_on_read->($_buffer, undef) if $_buffer;
}

method read {
	my $size=$_[1]//4096*4;
	#force a manual read into buffer
	IO::FD::sysread($_fh, $size, $_buffer);
	$_on_read->($_buffer, undef) if $_buffer;
}


method start {
	#method class for backend to override
}

method pause{
	#method class for backend to override
}

method _make_reader {

}

method pipe_to ($writer,$limit=undef){
	my $counter;
	\my @queue=$writer->queue;
	$self->on_read= sub {
		my $data=$_[0];	#Copy data
		$_[0]="";	#Consume input
		if(!$limit  or $#queue < $limit){
			#The next write cannot equal the limit so blaze ahead
			#with no callback,
			$writer->write($data);
		}
		else{
			#the next write will equal the limit,
			#use a callback
			$self->pause;	#Pause the reader
			$writer->write($data, sub{
				#restart the reader
				$self->start;
			});
		}
	};
	$writer; #Return writer to allow chaining
}
1;

__END__

=head1 NAME

uSAC::IO::Reader

=head1 SYNOPSIS

	use uSAC::IO;
	my $reader= uSAC::IO->reader(fileno $fh);
	
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
