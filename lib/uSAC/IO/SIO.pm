package uSAC::IO::SIO;
use strict;
use warnings;
use version; our $VERSION=version->declare("v0.1");

use feature qw<say state refaliasing>;
use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in inet_aton>;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use Errno qw(EAGAIN EINTR EINPROGRESS);
use Carp qw<carp>;


use Exporter qw<import>;

our @EXPORT_OK=qw<
	connect_inet
	sreader_
	swriter_
	writer_
	ctx_
	on_error_
	fh_
>;

our @EXPORT=qw<connect_inet>;
our %EXPORT_TAGS=(fields=>[qw<sreader_ swriter_ writer_ ctx_ on_error_ fh_>]);


use enum qw<sreader_ swriter_ writer_ ctx_ on_error_ fh_>;

sub new {
	my $package=shift//__PACKAGE__;
	#Attempt to located supported backends		
	my $self=[];
	my $fh=shift;
	my $fh2=shift//$fh;

	my %options=@_;

	bless $self, $package;
	#$self->[ctx_]=$ctx;
	fcntl $fh, F_SETFL, O_NONBLOCK;
	my $sreader=uSAC::IO::SReader->new($fh);
	$sreader->on_error=sub {$self->[on_error_]->&*};

	my $swriter=uSAC::IO::SWriter->new($fh2);
	$swriter->on_error=sub {$self->[on_error_]->&*};
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
########################
# sub ctx : lvalue{    #
#         $_[0][ctx_]; #
# }                    #
########################
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


sub connect_inet {
	&_inet;
}

1;


