package uSAC::SIO;
use strict;
use warnings;
use version; our $VERSION=version->declare("v0.1");

use feature qw<say state refaliasing>;
use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in inet_aton>;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use Errno qw(EAGAIN EINTR EINPROGRESS);
use Carp qw<carp>;

use AnyEvent;
use uSAC::SReader;
use uSAC::SWriter;

use Exporter qw<import>;

our @EXPORT_OK=qw<connect_inet connect_inet_datagram>;
our @EXPORT=@EXPORT_OK;

use enum qw<sreader_ swriter_ writer_ ctx_ on_error_ fh_>;

sub new {
	my $package=shift//__PACKAGE__;
	my $self=[];
	my $ctx=shift;
	my $fh=shift;

	my %options=@_;

	bless $self, $package;
	$self->[ctx_]=$ctx;
	fcntl $fh, F_SETFL, O_NONBLOCK;
	my $sreader=uSAC::SReader->new($ctx, $fh);
	$sreader->on_error=sub {&$self->[on_error_]};

	my $swriter=uSAC::SWriter->new($ctx, $fh);
	$swriter->on_error=sub {&$self->[on_error_]};
	$swriter->writer;	
	$self->[sreader_]=$sreader;
	$self->[swriter_]=$swriter;
	$self;
}

#methods
sub write {
	my $self=shift;
	$self->[swriter_]->write(@_);
}

sub pause{
	$_[0][sreader_]->pause;
	$_[0][swriter_]->pause;
}

sub start {
	$_[0][sreader_]->start;
}

sub pump {
	$_[0][sreader_]->pump;
}

sub writer {
	$_[0][swriter_]->writer;

}

#accessors
sub ctx : lvalue{
	$_[0][ctx_];
}
sub fh {
	$_[0][fh_];
}

sub on_error : lvalue {
	$_[0][on_error_];

}

sub on_drain : lvalue {
	$_[0][swriter_]->on_drain;

}

sub on_read : lvalue {
	$_[0][sreader_]->on_read;

}

sub on_eof : lvalue {
	$_[0][sreader_]->on_eof;

}
sub max_read_size :lvalue{
	$_[0][sreader_]->max_read_size($_[1]);
}

sub timing {
	my ($self, $read_time, $write_time, $clock)=@_;
	$self->[sreader_]->timing($read_time, $clock);
	$self->[swriter_]->timing($write_time, $clock);
}


#experimental
sub connect_inet {
	my ($ctx,$host,$port,$on_connect,$on_error)=@_;

	$on_connect//=sub{};
	$on_error//=sub{};

	socket my $fh, AF_INET, SOCK_STREAM, 0;

	fcntl $fh, F_SETFL, O_NONBLOCK;
	my $addr=pack_sockaddr_in $port, inet_aton $host;

	#Do non blocking connect 
	#A EINPROGRESS is expected due to non block
	my $res=connect $fh, $addr;
	unless($res){
		#EAGAIN for pipes
		if($! == EAGAIN or $! == EINPROGRESS){
			say " non blocking connect";
			my $cw;$cw=AE::io $fh, 1, sub {
				#Need to check if the socket has	
				my $sockaddr=getpeername $fh;
				undef $cw;
				if($sockaddr){
					$on_connect->($ctx,$fh);
				}
				else {
					#error
					say $!;
					$on_error->($ctx,$!);
				}
			};
			return;
		}
		else {
			say "Error in connect";
			warn "Counld not connect to host";
			#$self->[on_error_]();
			AnyEvent::postpone { 
				$on_error->($ctx,$!);
			};
			return;
		}
		return;
	}
	#handle immediate return of connect
	#my $sockaddr=getpeername $fh;
	AnyEvent::postpone {$on_connect->($ctx,$fh)};
}
sub connect_inet_datagram{
	my ($ctx,$host,$port,$on_connect,$on_error)=@_;

	$on_connect//=sub{};
	$on_error//=sub{};

	socket my $fh, AF_INET, SOCK_DGRAM, 0;

	fcntl $fh, F_SETFL, O_NONBLOCK;
	my $addr=pack_sockaddr_in $port, inet_aton $host;

	#Do non blocking connect 
	#A EINPROGRESS is expected due to non block
	my $res=connect $fh, $addr;
	unless($res){
		#EAGAIN for pipes
		if($! == EAGAIN or $! == EINPROGRESS){
			say " non blocking connect";
			my $cw;$cw=AE::io $fh, 1, sub {
				#Need to check if the socket has	
				my $sockaddr=getpeername $fh;
				undef $cw;
				if($sockaddr){
					$on_connect->($ctx,$fh);
				}
				else {
					#error
					say $!;
					$on_error->($ctx,$!);
				}
			};
			return;
		}
		else {
			say "Error in connect";
			warn "Counld not connect to host";
			#$self->[on_error_]();
			AnyEvent::postpone { 
				$on_error->($ctx,$!);
			};
			return;
		}
		return;
	}
	#handle immediate return of connect
	#my $sockaddr=getpeername $fh;
	AnyEvent::postpone {$on_connect->($ctx,$fh)};
}

1;


