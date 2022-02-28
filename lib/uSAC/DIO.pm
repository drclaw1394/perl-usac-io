package uSAC::DIO;
use strict;
use warnings;
use version; our $VERSION=version->declare("v0.1");

use feature qw<say state refaliasing>;
use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in inet_aton>;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use Errno qw(EAGAIN EINTR EINPROGRESS);
use Carp qw<carp>;

use Exporter qw<import>;

our @EXPORT_OK=qw<connect_inet bind_inet
	dreader_ dwriter_ writer_ ctx_ on_error_ fh_
>;
our @EXPORT=@EXPORT_OK;
our %EXPORT_TAGS=(fields=>[qw<dreader_ dwriter_ writer_ ctx_ on_error_ fh_>]);


use enum qw<dreader_ dwriter_ writer_ ctx_ on_error_ fh_>;

my $backend;
if(exists $main::{"AnyEvent::"}){
	$backend="uSAC::DIO::AE";
}
elsif(exists $main::{"IOASync::"}){
}
elsif(exists $main::{"IOMojo::"}){
}
else {
	carp "No event system detected. defaulting to AE";
	#set default to any event
	$backend="uSAC::DIO::AE";
}
my $sb=($backend."::DIO");
eval "require $sb";

{
	no strict qw<refs>;
	*_connect=*{"$sb"."::connect_inet"};
	*_bind=*{"$sb"."::bind_inet"};
}

my $rb=($backend."::DReader");
eval "require $rb";
my $wb=($backend."::DWriter");
eval "require $wb";

sub new {
	my $package=shift//__PACKAGE__;
	#Attempt to located supported backends		
	my $self=[];
	#my $ctx=shift;
	my $fh=shift;
	my $fh2=shift//$fh;

	my %options=@_;

	bless $self, $package;
	#$self->[ctx_]=$ctx;
	fcntl $fh, F_SETFL, O_NONBLOCK;
	my $dreader=$rb->new($fh);
	$dreader->on_error=sub {$self->[on_error_]->&*};

	my $dwriter=$wb->new( $fh2);
	$dwriter->on_error=sub {$self->[on_error_]->&*};
	$dwriter->writer;	
	$self->[dreader_]=$dreader;
	$self->[dwriter_]=$dwriter;
	$self;
}

#methods
sub write {
	my $self=shift;
	$self->[dwriter_]->write(@_);
}

sub pause{
	$_[0][dreader_]->pause;
	$_[0][dwriter_]->pause;
}

sub start {
	$_[0][dreader_]->start;
}

sub pump {
	$_[0][dreader_]->pump;
}

sub writer {
	$_[0][dwriter_]->writer;

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
	$_[0][dwriter_]->on_drain;

}

sub on_read : lvalue {
	$_[0][dreader_]->on_message;

}

sub on_eof : lvalue {
	$_[0][dreader_]->on_eof;

}
sub max_read_size :lvalue{
	$_[0][dreader_]->max_read_size($_[1]);
}

sub timing {
	my ($self, $read_time, $write_time, $clock)=@_;
	$self->[dreader_]->timing($read_time, $clock);
	$self->[dwriter_]->timing($write_time, $clock);
}


sub connect_inet {
	&_connect;
}

sub bind_inet {
	&_bind;
}
1;


