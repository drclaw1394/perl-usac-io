use Object::Pad;
package uSAC::IO::AE::DReader;
class uSAC::IO::AE::DReader :isa(uSAC::IO::DReader);
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Errno qw(EAGAIN EINTR EINPROGRESS);
use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in inet_aton>;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use Data::Dumper;
use constant DEBUG=>0;

field $_rw;

#destroy io watcher, 
method pause :override {
	undef $_rw;
	$self;
}




method start :override ($fh=undef) {
	$self->rfh=$fh if $fh;
	$_rw= AE::io $self->rfh, 0, $self->_make_reader;
	$self;
}

#alias variables and create io watcher
method _make_reader :override {
	\my $on_read=\$self->on_read; #alias cb 
	\my $on_error=\$self->on_error;
	#\my $rw=\$self->[rw_];
	#\my $buf=\$self->[buffer_];
	\my $max_read_size=\$self->max_read_size;
	\my $rfh=$self->rfh;		
	\my $time=\$self->time;
	\my $clock=\$self->clock;
	\my $flags=\$self->flags;
	$_rw=undef;
	$self->reader=sub {
		#$self->[time_]=$Time;	#Update the last access time
		$time=$clock;
		my $buf="";
		my $addr =recv($rfh, $buf, $max_read_size,$flags);
		defined($addr) and return($on_read and $on_read->($buf, $addr));
		($! == EAGAIN or $! == EINTR) and return;

		warn "ERROR IN READER" if DEBUG;
		$_rw=undef;
		$on_error->($!);
		return;
	};
}


#################################################################################
# sub pipe {                                                                    #
#         #Argument is a writer                                                 #
#         my ($self, $writer, $limit)=@_;                                       #
#         my $counter;                                                          #
#         \my @queue=$writer->queue;                                            #
#         $self->on_read= sub {                                                 #
#                 if(!$limit  or $#queue < $limit){                             #
#                         #The next write cannot equal the limit so blaze ahead #
#                         #with no callback,                                    #
#                         $writer->write($_[0]);                                #
#                 }                                                             #
#                 else{                                                         #
#                         #the next write will equal the limit,                 #
#                         #use a callback                                       #
#                         $self->pause;   #Pause the reader                     #
#                         $writer->write($_[0], sub{                            #
#                                 #restart the reader                           #
#                                 $self->start;                                 #
#                         });                                                   #
#                 }                                                             #
#         };                                                                    #
#         $writer; #Return writer to allow chaining                             #
# }                                                                             #
#                                                                               #
#################################################################################

1;
