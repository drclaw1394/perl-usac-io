package uSAC::IO::AE::DReader;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Errno qw(EAGAIN EINTR EINPROGRESS);
use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in inet_aton>;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use Data::Dumper;
use constant DEBUG=>0;


use parent "uSAC::IO::DReader";
use uSAC::IO::Reader  qw<:fields>;	#Import field names
#use uSAC::IO::DReader qw<:fields>;	#Import field names

#pass in fh, ctx, on_message, on_eof, on_error
#Returns a sub which is called with a buffer, an optional callback and argument

use constant KEY_OFFSET=>uSAC::IO::DReader::KEY_OFFSET+uSAC::IO::DReader::KEY_COUNT;

use enum ("rw_=".KEY_OFFSET, qw<>);

use constant KEY_COUNT=>rw_-rw_+1;


sub new {
	my $package=shift//__PACKAGE__;
	my $self=$package->SUPER::new(@_);
	$self->[rw_]=undef;
	$self;
}

#destroy io watcher, 
sub pause{
	undef $_[0][rw_];
	$_[0];
}


sub flags : lvalue{
	$_[0][uSAC::IO::DReader::flags_];
}


sub start {
	$_[0][rfh_]=$_[1] if $_[1];
	$_[0][rw_]= AE::io $_[0][rfh_], 0, $_[0][reader_]//$_[0]->_make_reader;
	$_[0];	#Make chainable
}

#alias variables and create io watcher
sub _make_reader {
	my $self=shift;
	
	\my $on_read=\$self->[on_read_]; #alias cb 
	\my $on_error=\$self->[on_error_];
	\my $rw=\$self->[rw_];
	#\my $buf=\$self->[buffer_];
	\my $max_read_size=\$self->[max_read_size_];
	\my $rfh=$self->[rfh_];		
	\my $time=\$self->[time_];
	\my $clock=\$self->[clock_];
	\my $flags=\$self->[uSAC::IO::DReader::flags_];
	$rw=undef;
	$self->[reader_]=sub {
		#$self->[time_]=$Time;	#Update the last access time
		$$time=$$clock;
		my $buf="";
		my $addr =recv($rfh, $buf, $max_read_size,$flags);
		defined($addr) and return($on_read and $on_read->($buf, $addr));
		($! == EAGAIN or $! == EINTR) and return;

		warn "ERROR IN READER" if DEBUG;
		$rw=undef;
		$on_error->($!);
		return;
	};
}

########################################################################
# sub bind_inet {                                                      #
#         my ($package, $fh, $host, $port, $on_connect, $on_error)=@_; #
#         $on_connect//=sub{};                                         #
#         $on_error//=sub{};                                           #
#                                                                      #
#         #socket my $fh, AF_INET, SOCK_DGRAM, 0;                      #
#                                                                      #
#         #fcntl $fh, F_SETFL, O_NONBLOCK;                             #
#                                                                      #
#         my $addr=pack_sockaddr_in $port, inet_aton $host;            #
#                                                                      #
#         my $res=bind    $fh, $addr;                                  #
#         unless($res){                                                #
#                 warn "Could not bind";                               #
#                 #$self->[on_error_]();                               #
#                 AnyEvent::postpone {                                 #
#                         $on_error->($!);                             #
#                 };                                                   #
#                 return;                                              #
#         }                                                            #
#         AnyEvent::postpone {$on_connect->($fh)};                     #
#                                                                      #
# }                                                                    #
#                                                                      #
# sub connect_inet {                                                   #
#         my ($package,$host,$port,$on_connect,$on_error)=@_;          #
#                                                                      #
#         $on_connect//=sub{};                                         #
#         $on_error//=sub{};                                           #
#                                                                      #
#         socket my $fh, AF_INET, SOCK_DGRAM, 0;                       #
#                                                                      #
#         fcntl $fh, F_SETFL, O_NONBLOCK;                              #
#                                                                      #
#         my $addr=pack_sockaddr_in $port, inet_aton $host;            #
#                                                                      #
#         my $local=pack_sockaddr_in 6060, inet_aton "127.0.0.1";      #
#         #Do non blocking connect                                     #
#         #A EINPROGRESS is expected due to non block                  #
#         ###################################                          #
#         # say "Binding to local address"; #                          #
#         # unless(bind $fh, $local){       #                          #
#         #         say "bind error $!";    #                          #
#         # }                               #                          #
#         ###################################                          #
#         my $res=connect $fh, $addr;                                  #
#         unless($res){                                                #
#                 #EAGAIN for pipes                                    #
#                 if($! == EAGAIN or $! == EINPROGRESS){               #
#                         say " non blocking connect";                 #
#                         my $cw;$cw=AE::io $fh, 1, sub {              #
#                                 #Need to check if the socket has     #
#                                 my $sockaddr=getpeername $fh;        #
#                                 undef $cw;                           #
#                                 if($sockaddr){                       #
#                                         $on_connect->($fh);          #
#                                 }                                    #
#                                 else {                               #
#                                         #error                       #
#                                         say $!;                      #
#                                         $on_error->($!);             #
#                                 }                                    #
#                         };                                           #
#                         return;                                      #
#                 }                                                    #
#                 else {                                               #
#                         say "Error in connect";                      #
#                         warn "Counld not connect to host";           #
#                         #$self->[on_error_]();                       #
#                         AnyEvent::postpone {                         #
#                                 $on_error->($!);                     #
#                         };                                           #
#                         return;                                      #
#                 }                                                    #
#                 return;                                              #
#         }                                                            #
#         AnyEvent::postpone {$on_connect->($fh)};                     #
# }                                                                    #
########################################################################

sub pipe {
	#Argument is a writer
	my ($self, $writer, $limit)=@_;
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
