package uSAC::IO::Reader;
use strict;
use warnings;
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
#Returns a sub which is called with a buffer, an optional callback and argument

use constant KEY_OFFSET=>0;
use enum ("ctx_=".KEY_OFFSET, qw<rfh_ reader_ time_ clock_ on_read_ on_eof_ on_error_ max_read_size_ buffer_ >);

use constant KEY_COUNT=>buffer_-ctx_+1;

our @fields=qw<ctx_ rfh_ reader_ time_ clock_ on_read_ on_eof_ on_error_ max_read_size_ buffer_>;

our @EXPORT_OK=@fields;
our %EXPORT_TAGS=("fields"=>\@fields);
		
sub new {
	my $package=shift//__PACKAGE__;
	
	my $self=[];#[@_];
	$self->[rfh_]=shift;
        fcntl $self->[rfh_], F_SETFL, O_NONBLOCK;

	$self->[on_read_]//=sub {$self->pause};
	$self->[on_error_]//= $self->[on_eof_]//=sub{};

	$self->[max_read_size_]//=4096;
	$self->[buffer_]="";

	
	my $time=0;
	$self->[time_]=\$time;
	$self->[clock_]=\$time;

	bless $self, $package;
}

# Accessor API
#
#Set the external variables to use as clock source and timer
sub timing {
	my $self=shift;
	$self->@[time_, clock_]=@_;
}

sub on_read : lvalue {
	$_[0][on_read_];
}

sub on_eof : lvalue {
	$_[0][on_eof_];
}

sub on_error : lvalue{
	$_[0][on_error_];
}

sub max_read_size :lvalue{
	$_[0][max_read_size_];
}
sub buffer :lvalue{
	$_[0][buffer_];
}


#manually call on_read if buffer is not empty
sub pump {
	$_[0][on_read_]->(undef, $_[0][buffer_]) if $_[0][buffer_];
}


sub start {
	#sub class for backend to override
}

sub pause{
	#sub class for backend to override
}

sub _make_reader {

}

1;

__END__
