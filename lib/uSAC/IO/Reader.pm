use Object::Pad;
package uSAC::IO::Reader;
class uSAC::IO::Reader;

use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Log::ger;
use Log::OK;

use Errno qw(EAGAIN EINTR);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Data::Dumper;
use Exporter "import";

#pass in fh, ctx, on_read, on_eof, on_error
#Returns a method which is called with a buffer, an optional callback and argument

field $_ctx;
field $_fh :param :mutator;
field $_reader 	:mutator;
field $_time	:mutator;
field $_clock	 :mutator;
field $_on_read :mutator;
field $_on_eof  :mutator;
field $_on_error :mutator;
field $_max_read_size :mutator;
field $_buffer	:mutator;
		
	
BUILD{
        fcntl $_fh, F_SETFL, O_NONBLOCK;

	$_on_read//=sub {$self->pause};
	$_on_error//= $_on_eof//=sub{};

	$_max_read_size//=4096;
	$_buffer="";

	
	my $time=0;
	$_time=\$time;
	$_clock=\$time;
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


method start {
	#method class for backend to override
}

method pause{
	#method class for backend to override
}

method _make_reader {

}

method pipe  ($writer,$limit=undef){
	my $counter;
	\my @queue=$writer->queue;
	$self->on_read= sub {
		if(!$limit  or $#queue < $limit){
			#The next write cannot equal the limit so blaze ahead
			#with no callback,
			$writer->write($_[0]);
		}
		else{
			#the next write will equal the limit,
			#use a callback
			$self->pause;	#Pause the reader
			$writer->write($_[0], sub{
				#restart the reader
				$self->start;
			});
		}
	};
	$writer; #Return writer to allow chaining
}
1;

__END__
