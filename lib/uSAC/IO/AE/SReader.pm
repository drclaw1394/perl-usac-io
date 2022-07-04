package uSAC::IO::AE::SReader;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Log::ger;
use Log::OK;

use Errno qw(EAGAIN EINTR);
use Data::Dumper;
use Exporter "import";

use parent "uSAC::IO::SReader";
use uSAC::IO::Reader qw<:fields>;	#Import field names

use constant KEY_OFFSET=>uSAC::IO::Reader::KEY_OFFSET + uSAC::IO::Reader::KEY_COUNT;
use enum ("rw_=".KEY_OFFSET, qw<>);

use constant KEY_COUNT=>rw_-rw_+1;

		
sub new {
	my $package=shift//__PACKAGE__;
	my $self=$package->SUPER::new(@_);
	
	$self->[rw_]=undef;
	#bless $self, $package;
	$self;
}

sub start {
	$_[0][rfh_]=$_[1] if $_[1];
	$_[0][rw_]= AE::io $_[0][rfh_], 0, $_[0][reader_]//$_[0]->_make_reader;
	$_[0];	#Make chainable
}

sub _make_reader {
#alias variables and create io watcher
	my $self=shift;
	
	#\my $ctx=\$self->[ctx_];
	\my $on_read=\$self->[on_read_]; #alias cb 
	\my $on_eof=\$self->[on_eof_];
	\my $on_error=\$self->[on_error_];
	\my $rw=\$self->[rw_];
	\my $buf=\$self->[buffer_];
	\my $max_read_size=\$self->[max_read_size_];
	\my $rfh=\$self->[rfh_];		
	\my $time=\$self->[time_];
	\my $clock=\$self->[clock_];
	my $len;
	$rw=undef;
	$self->[reader_]=sub {
		#$self->[time_]=$Time;	#Update the last access time
		$$time=$$clock;
		$len = sysread($rfh, $buf, $max_read_size, length $buf );
		$len>0 and return($on_read and $on_read->($buf));
		$len==0 and return($on_eof and $on_eof->($buf));
		($! == EAGAIN or $! == EINTR) and return;

		Log::OK::ERROR and log_error "ERROR IN READER: $!";
		$rw=undef;
		$on_error->(undef, $buf);
		return;
	};
}

#in the AE implementation, pause destroys the io watcher, which pauses the read
#events
sub pause{
	undef $_[0][rw_];
	$_[0];	#Make chainable
}

sub pipe {
	#Argument is a writer
	my ($self,$writer,$limit)=@_;
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
