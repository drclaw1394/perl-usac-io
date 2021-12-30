package uSAC::SReader;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Errno qw(EAGAIN EINTR);
use Data::Dumper;
use constant DEBUG=>0;

#pass in fh, ctx, on_read, on_eof, on_error
#Returns a sub which is called with a buffer, an optional callback and argument

use enum (qw<ctx_ rfh_ on_read_ on_eof_ on_error_ max_read_size_ rw_ buffer_ >);

		
sub new {
	my $package=shift//__PACKAGE__;
	
	my $self=[@_];
	$self->[on_read_]//=sub {$self->pause};
	$self->[on_eof_]//=sub{};
	$self->[on_error_]//=sub{};
	$self->[max_read_size_]//=4096;
	$self->[rw_]=undef;
	$self->[buffer_]="";
	bless $self, $package;
}

sub ctx : lvalue{
	$_[0][ctx_];
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


#alias variables and create io watcher
sub start {
	my $self=shift;
	
	\my $ctx=\$self->[ctx_];
	\my $on_read=\$self->[on_read_]; #alias cb 
	\my $on_eof=\$self->[on_eof_];
	\my $on_error=\$self->[on_error_];
	\my $rw=\$self->[rw_];
	\my $buf=\$self->[buffer_];
	\my $max_read_size=\$self->[max_read_size_];
	my $rfh=shift//$self->[rfh_];		
	my $len;
	$rw=undef;
	$rw = AE::io $rfh, 0, sub {
		#$self->[time_]=$Time;	#Update the last access time
		$len = sysread($rfh, $buf, $max_read_size, length $buf );
		#say $buf;
		if($len>0){
			$on_read->($ctx, $buf, 1) if $on_read;
		}
		#when(0){
		elsif($len==0){
			#say "read len is zero";
			#End of file
			#say "END OF  READER";
			$rw=undef;
			$on_eof->($ctx, $buf, 0);
		}
		else {
			#potential error
			#say "ERROR";
			return if $! == EAGAIN or $! == EINTR;
			warn "ERROR IN READER" if DEBUG;
			$rw=undef;
			$on_error->($ctx, $buf, undef);
		}
	};
	$self;
}

#destroy io watcher, 
sub pause{
	undef $_[0][rw_];
	$_[0];
}

1;

__END__

=head1 NAME

SReader 

=head1 SYNOPSIS

	use uSAC::SReader;

	#Socket/pipe/fifo already opened
	my $fh;		

	#Create the reader with the handle
	my $sr=uSAC::SReader->new($fh);

	#Set on read and on eof
	$sr->on_read=sub {print $_[1]; $_[1]=""};
	$sr->on_eof=sub {close $fh;

=head1 DESCRIPTION

SReader (Stream Reader) is built around perl features (some experimental) and AnyEvent to give efficient reading of event based file handles. This means it

=over

=item Aliasing

Aliasing benefits of the C<@_> array to pass data around without copies or references how you maniupate the read data.

The main reading subroutine also aliases all internal variables from the OO interface. This means not dereferenceing or array index lookups are performed in a hot part of the code

=item Array base Object

No hash objects used here. More speed, less memory

=item lvalues

Accessors functions return lvalues. So this means you can assign to internal fields directly
ie
	#instead of 
	#	$object->field("value")
	#
	#do this
	#	$object->field="value";

It also allows aliasing of the field. Which means the value can be changed efficiently on the fly without a function call

	#set up an alias
	#	\my $alias=\$object->field;
	#Later in the program can set the value via the alias
	#	$alias="new value"
	

=back


=head1 API

=over

=item new

Constructor for SReader object. Requires a handle to a socket/pipe/fifo in non blocking mode


