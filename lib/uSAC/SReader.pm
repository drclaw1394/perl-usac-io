package uSAC::SReader;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings "experimental";

use AnyEvent;
use Errno qw(EAGAIN EINTR);
use constant DEBUG=>0;
use constant MAX_READ_SIZE=>16;

#pass in fh, ctx, on_read, on_eof, on_error
#Returns a sub which is called with a buffer, an optional callback and argument

use enum (qw<ctx_ on_read_ on_eof_ on_error_ cancel_ max_read_size_>);

		
sub new {
	my $package=shift//__PACKAGE__;
	my $self=&make_sio_reader;
	bless $self, $package;
}

sub ctx : lvalue{
	$_[0][ctx_]->$*;
}

sub on_read : lvalue {
	$_[0][on_read_]->$*;
}

sub on_eof : lvalue {
	$_[0][on_eof_]->$*;
}

sub on_error : lvalue{
	$_[0][on_error_]->$*;
}

sub max_read_size :lvalue{
	$_[0][max_read_size_]->$*;
}

sub cancel {
	&{$_[0][cancel_]};
}


#setup read watcher
sub make_sio_reader{
	my $sub=sub {
		my $ctx=$_[0];
		my $rfh=$_[1];
		my $on_read=$_[2];
		my $on_eof=$_[3]//sub{
			print "Reader Done\n";
			#close socket
		};
		my $on_error=$_[4]//sub{
			#close socket
			print "Error\n";
		};
		my $rw;
		my $buf="";
		my $len;
		my $max_read_size=16;



		$rw = AE::io $rfh, 0, sub {
			#$self->[time_]=$Time;	#Update the last access time
			$len = sysread( $rfh, $buf, $max_read_size, length $buf );
			#say $buf;
			if($len>0){
				$on_read->($ctx, $buf) if $on_read;
			}
			#when(0){
			elsif($len==0){
				#say "read len is zero";
				#End of file
				#say "END OF  READER";
				$rw=undef;
				$on_eof->($ctx, $buf);
			}
			else {
				#potential error
				#say "ERROR";
				return if $! == EAGAIN or $! == EINTR;
				warn "ERROR IN READER" if DEBUG;
				$rw=undef;
				$on_error->($ctx, $buf);
			}
		};
		#return a canceller
	
		return [\$ctx, \$on_read, \$on_eof, \$on_error, sub {undef $rw; $buf;}, \$max_read_size];
	};
	&$sub;
}


1;
