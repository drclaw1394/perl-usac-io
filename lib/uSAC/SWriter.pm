package uSAC::SWriter;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings "experimental";

use AnyEvent;
use Errno qw(EAGAIN EINTR);
use constant DEBUG=>0;


#pass in fh, ctx, on_read, on_eof, on_error
#Returns a sub which is called with a buffer, an optional callback and argument

use enum (qw<ctx_ wfh_ on_error_ writer_ ww_ queue_>);


sub new {
	my $package=shift//__PACKAGE__;
	my $self=[@_];
	$self->[on_error_]//=sub{};
	$self->[writer_]=undef;
	$self->[ww_]=undef;
	$self->[queue_]=[];
	bless $self, $package;
}

#return or create an return writer
sub writer {
	$_[0][writer_]//=$_[0]->_make_writer;
}


sub ctx : lvalue{
	$_[0][ctx_];
}

###############################
# sub on_eof : lvalue {       #
#         $_[0][on_eof_]->$*; #
# }                           #
###############################

sub on_error : lvalue{
	$_[0][on_error_];
}

#pause any automatic writing
sub pause {
	$_[0]->[ww_]=undef;
}


#OO interface
sub write {
	shift;
	&{$_[0][writer_]};
}

#internal
#Aliases variables for (hopefully) faster access in repeated calls
sub _make_writer {
	my $self=shift;
	\my $ctx=\$self->[ctx_];#$_[0];
	my $wfh=$self->[wfh_];
	\my $on_error=\$self->[on_error_];#$_[3]//sub{

	\my $ww=\$self->[ww_];
	\my @queue=$self->[queue_];

	my $w;
	my $offset=0;
	#Arguments are buffer and callback.
	#do not call again until callback is called
	#if no callback is provided, the session dropper is called.
	#
	sub {
		use integer;
		$_[0]//return;				#undefined input. was a stack reset
		#my $dropper=$on_done;			#default callback

		my $cb= $_[1];
		my $arg=$_[2]//__SUB__;			#is this sub unless provided

		$offset=0;				#offset allow no destructive
							#access to input
		if(!$ww){
			#no write watcher so try synchronous write
			$offset+=$w = syswrite($wfh, $_[0], length($_[0])-$offset, $offset);
			#$offset+=$w;
			if($offset==length $_[0]){
				#say "FULL WRITE NO APPEND";
				$cb->($arg) if $cb;
				return;
			}

			if(!defined($w) and $! != EAGAIN and $! != EINTR){
				#this is actual error
				warn "ERROR IN WRITE NO APPEND" if DEBUG;
				warn $! if DEBUG;
				#actual error		
				$ww=undef;
				@queue=();	#reset queue for session reuse
				$cb->(undef) if $cb;
				$on_error->($ctx);
				#uSAC::HTTP::Session::drop $session, "$!";
				return;
			}

			#either a partial write or an EAGAIN situation

			#say "EAGAIN or partial write";
			#If the write was only partial, or had a async 'error'
			#push the buffer to setup events
			push @queue,[$_[0], $offset, $cb, $arg];
			#say "PARTIAL WRITE Synchronous";
			my $entry;
			$ww = AE::io $wfh, 1, sub {
				$entry=$queue[0];
				\my $buf=\$entry->[0];
				\my $offset=\$entry->[1];
				\my $cb=\$entry->[2];
				\my $arg=\$entry->[3];
				#say "watcher cb";
				$w = syswrite $wfh, $buf, length($buf)-$offset, $offset;
				if($offset==length $buf) {
					#say "FULL async write";
					shift @queue;
					undef $ww unless @queue;
					$cb->($arg) if $cb;
					return;
				}

				if(!defined($w) and $! != EAGAIN and $! != EINTR){
					#this is actual error
					warn "ERROR IN EVENT WRITE" if DEBUG;
					warn $! if DEBUG;
					#actual error		
					$ww=undef;
					@queue=();	#reset queue for session reuse
					$cb->(undef);
					$on_error->($ctx);
					return;
				}
			};

			return
		}
		else {
			#watcher existing, add to queue
			push @queue, [$_[0],0,$cb,$arg];
		}

	};
}

1;
