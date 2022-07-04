package uSAC::IO::AE::SWriter;
use strict;
use warnings;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;
#use Scalar::Util qw<weaken>;


use AnyEvent;
use Log::ger;
use Log::OK;
use Errno qw(EAGAIN EINTR);
use parent "uSAC::IO::Writer";
use uSAC::IO::Writer qw<:fields>;


#pass in fh, ctx, on_read, on_eof, on_error
#Returns a sub which is called with a buffer, an optional callback and argument

#use enum (qw<ctx_ wfh_ time_ clock_ on_drain_ on_error_ writer_ ww_ queue_>);

use constant KEY_OFFSET=>uSAC::IO::Writer::KEY_OFFSET + uSAC::IO::Writer::KEY_COUNT;
use enum ("ww_=".KEY_OFFSET, qw<>);

use constant KEY_COUNT=>ww_-ww_+1;

sub new {
	my $package=shift//__PACKAGE__;
	my $self=$package->SUPER::new(@_);
	#$self->[ww_]=undef;

}

sub set_write_handle {
	my ($self, $wh)=@_;
	$self->[wfh_]=$wh;
	$self->[ww_]=undef;

}

#pause any automatic writing
sub pause {
	$_[0]->[ww_]=undef;
	$_[0];
}

#internal
#Aliases variables for (hopefully) faster access in repeated calls
sub _make_writer {
	my $self=shift;
	#\my $ctx=\$self->[ctx_];#$_[0];
	\my $wfh=\$self->[wfh_];
	\my $on_error=\$self->[on_error_];#$_[3]//sub{

	\my $ww=\$self->[ww_];
	\my @queue=$self->[queue_];
	\my $time=\$self->[time_];
	\my $clock=\$self->[clock_];

	my $w;
	my $offset=0;
	#Arguments are buffer and callback.
	#do not call again until callback is called
	#if no callback is provided, the session dropper is called.
	#
	sub {
		use integer;
		no warnings "recursion";
		$_[0]//return;				#undefined input. was a stack reset
		#my $dropper=$on_done;			#default callback

		my $cb= $_[1];
		my $arg=1;#$_[2]//__SUB__;			#is this sub unless provided

		$offset=0;				#offset allow no destructive
							#access to input
		unless($wfh){
			Log::OK::ERROR and log_error "SIO Writer: file handle undef, but write called from". join ", ", caller;
			return;
		}
		if(!$ww){
			#no write watcher so try synchronous write
			$$time=$$clock;
			$offset+=$w = syswrite($wfh, $_[0]);#, length($_[0])-$offset, $offset);
			$offset==length($_[0]) and return($cb and $cb->($arg));


                        ########################################
                        # if($offset==length $_[0]){           #
                        #         #say "FULL WRITE NO APPEND"; #
                        #         $cb->($arg) if $cb;          #
                        #         return;                      #
                        # }                                    #
                        ########################################

			if(!defined($w) and $! != EAGAIN and $! != EINTR){
				#this is actual error
				Log::OK::ERROR and log_error "SIO Writer: ERROR IN WRITE NO APPEND $!";
				#actual error		
				$ww=undef;
				$wfh=undef;
				@queue=();	#reset queue for session reuse
				$on_error->($!);
				$cb->() if $cb;
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
				unless($wfh){
					Log::OK::ERROR and log_error "SIO Writer: file handle undef, but write watcher still active";
					return;
				}
				$entry=$queue[0];
				\my $buf=\$entry->[0];
				\my $offset=\$entry->[1];
				\my $cb=\$entry->[2];
				#\my $arg=\$entry->[3];
				#say "watcher cb";
				$$time=$$clock;
				$offset+=$w = syswrite $wfh, $buf, length($buf)-$offset, $offset;
				if($offset==length $buf) {
					#say "FULL async write";
					shift @queue;
					undef $ww unless @queue;
					$cb->($entry->[3]) if $cb;
					return;
				}

				if(!defined($w) and $! != EAGAIN and $! != EINTR){
					#this is actual error
					Log::OK::ERROR and log_error "SIO Writer: ERROR IN WRITE $!";
					#actual error		
					$ww=undef;
					$wfh=undef;
					@queue=();	#reset queue for session reuse
					$on_error->($!);
					$cb->();
					return;
				}
			};

			return
		}
		else {
			#watcher existing, add to queue
			push @queue, [$_[0],0,$cb,$arg];
			#weaken $queue[$#queue][2];
		}

	};
}
1;
