package uSAC::IO::Writer;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

#use Scalar::Util qw<weaken>;


use AnyEvent;
use Log::ger;
use Log::OK;
use Errno qw(EAGAIN EINTR);

use Exporter "import";

use constant KEY_OFFSET=>0;
use enum ("ctx_=".KEY_OFFSET, qw<wfh_ time_ clock_ on_drain_ on_eof_ on_error_ writer_ queue_ >);

use constant KEY_COUNT=>queue_-ctx_+1;


my @fields=qw<ctx_ wfh_ time_ clock_ on_drain_ on_eof_ on_error_ writer_ queue_>;

our @EXPORT_OK=@fields;
our %EXPORT_TAGS=("fields"=>\@fields);

#use enum (qw<ctx_ wfh_ time_ clock_ on_drain_ on_error_ writer_ queue_>);


sub new {
	say __PACKAGE__." new";
	my $package=shift//__PACKAGE__;
	my $self=[];#[@_];
	$self->[wfh_]=shift;
        fcntl $self->[wfh_], F_SETFL, O_NONBLOCK;
	$self->[on_drain_]//=$self->[on_error_]//=sub{};
	#$self->[writer_]=undef;
	$self->[queue_]=[];
	my $time=0;

	$self->[time_]=\$time;
	$self->[clock_]=\$time;

	$self=bless $self, $package;
	#say "IN Writer new: ".$self;
	$self->[writer_]=$self->_make_writer;
	$self;
}


sub timing {
	my $self=shift;
	$self->@[time_, clock_]=@_;
}

#return or create an return writer
sub writer {
	$_[0][writer_]//=$_[0]->_make_writer;
}

#OO interface
sub write {
	my $self=shift;
	&{$self->[writer_]};
}



###############################
# sub on_eof : lvalue {       #
#         $_[0][on_eof_]->$*; #
# }                           #
###############################

sub on_error : lvalue{
	$_[0][on_error_];
}

sub on_drain : lvalue{
	$_[0][on_drain_];
}


#SUB CLASS SPECIFIC
#
sub pause {

}

sub set_write_handle {

}

sub _make_writer {
	say "IN IO WRITER make writer";
}
sub queue {
	$_[0][queue_];
}

1;

