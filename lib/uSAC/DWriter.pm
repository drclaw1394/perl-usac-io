package uSAC::DWriter;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Errno qw(EAGAIN EINTR);
use constant DEBUG=>0;


#pass in fh, ctx, on_read, on_eof, on_error
#Returns a sub which is called with a buffer, an optional callback and argument

use enum (qw<ctx_ wfh_ time_ clock_ on_drain_ on_error_ writer_ ww_ queue_>);


sub new {
	my $package=shift//__PACKAGE__;
	my $self=[@_];
	$self->[on_drain_]//=sub{};
	$self->[on_error_]//=sub{};
	$self->[writer_]=undef;
	$self->[ww_]=undef;
	$self->[queue_]=[];
	my $time=0;
	$self->[time_]=\$time;
	$self->[clock_]=\$time;
	bless $self, $package;
	$self->writer;		#create writer;
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

sub on_drain : lvalue{
	$_[0][on_drain_];
}

#pause any automatic writing
sub pause {
	$_[0]->[ww_]=undef;
}


#OO interface
sub write {
	my $self=shift;
	&{$self->[writer_]};
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
	\my $time=\$self->[time_];
	\my $clock=\$self->[clock_];

	my $w;
	my $offset=0;
	my $flags=0;
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
			$$time=$$clock;
			$offset+= $w= send $wfh, $_[0], $flags;
			$offset==length($_[0]) and return($cb and $cb->($arg));

			#TODO: DO we need to restructure on ICMP results for a unreachable host, connection refused, etc?
			if(!defined($w) and $! != EAGAIN and $! != EINTR){
				#this is actual error
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
				$$time=$$clock;
				#$offset+=$w = syswrite $wfh, $buf, length($buf)-$offset, $offset;
				$offset+= $w= send $wfh, substr($buf,$offset), $flags;
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
