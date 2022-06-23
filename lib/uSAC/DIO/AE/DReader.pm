package uSAC::DIO::AE::DReader;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Errno qw(EAGAIN EINTR);
use Data::Dumper;
use constant DEBUG=>0;

#pass in fh, ctx, on_message, on_eof, on_error
#Returns a sub which is called with a buffer, an optional callback and argument

use constant KEY_OFFSET=>0;

use enum ("ctx_=".KEY_OFFSET, qw< rfh_ time_ clock_ on_read_ on_error_ max_read_size_ rw_  flags_>);

use constant KEY_COUNT=>flags_-ctx_+1;


sub new {
	my $package=shift//__PACKAGE__;
	
	my $self=[];
	$self->[rfh_]=shift;
	$self->[on_read_]//=sub {$self->pause};
	$self->[on_error_]//=sub{};
	$self->[max_read_size_]//=4096;
	$self->[rw_]=undef;
	my $time=0;;
	$self->[time_]=\$time;
	$self->[clock_]=\$time;
	bless $self, $package;
}

sub on_read : lvalue {
	$_[0][on_read_];

}

sub timing {
	my $self=shift;
	$self->@[time_, clock_]=@_;
}

########################
# sub ctx : lvalue{    #
#         $_[0][ctx_]; #
# }                    #
########################

#destroy io watcher, 
sub pause{
	undef $_[0][rw_];
	$_[0];
}

sub on_error : lvalue{
	$_[0][on_error_];
}

sub flags : lvalue{
	$_[0][flags_];
}

sub max_read_size : lvalue{
	$_[0][max_read_size_];
}


#alias variables and create io watcher
sub start {
	my $self=shift;
	
	#\my $ctx=\$self->[ctx_];
	\my $on_read=\$self->[on_read_]; #alias cb 
	\my $on_error=\$self->[on_error_];
	\my $rw=\$self->[rw_];
	#\my $buf=\$self->[buffer_];
	\my $max_read_size=\$self->[max_read_size_];
	my $rfh=shift//$self->[rfh_];		
	\my $time=\$self->[time_];
	\my $clock=\$self->[clock_];
	my $flags=$self->[flags_];
	$rw=undef;
	$rw = AE::io $rfh, 0, sub {
		#$self->[time_]=$Time;	#Update the last access time
		$$time=$$clock;
		my $buf="";
		my $addr =recv($rfh, $buf, $max_read_size,$flags);
		defined($addr) and return($on_read and $on_read->($buf,$addr));
		($! == EAGAIN or $! == EINTR) and return;

		warn "ERROR IN READER" if DEBUG;
		$rw=undef;
		$on_error->($!);
		return;
	};
	$self;
}

1;
