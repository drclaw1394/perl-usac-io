use Object::Pad;
class uSAC::IO::AE::SWriter :isa(uSAC::IO::SWriter);
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Log::ger;
use Log::OK;
use Errno qw(EAGAIN EINTR);
use parent "uSAC::IO::Writer";
use uSAC::IO::Writer qw<:fields>;


field $_ww;		# Actual new variable for sub class
field $_wfh_ref;

BUILD {
	$_wfh_ref=\$self->fh;
}

method set_write_handle :override ($wh){
	$$_wfh_ref=$wh;
	$_ww=undef;

}

#pause any automatic writing
method pause :override {
	$_ww=undef;
	$self;
}

#internal
#Aliases variables for (hopefully) faster access in repeated calls
method _make_writer {
	\my $wfh=$_wfh_ref;#\$self->wfh;	#refalias
	\my $on_error=\$self->on_error;#$_[3]//method{

	#\my $ww=\$self->[ww_];
	\my @queue=$self->queue;
	\my $time=$self->time;
	\my $clock=$self->clock;

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
		my $arg=1;#$_[2]//__SUB__;			#is this method unless provided

		$offset=0;				#offset allow no destructive
							#access to input
		unless($wfh){
			Log::OK::ERROR and log_error "SIO Writer: file handle undef, but write called from". join ", ", caller;
			return;
		}
		if(!$_ww){
			#no write watcher so try synchronous write
			$time=$clock;
			$offset+=$w = syswrite($wfh, $_[0]);
			$offset==length($_[0]) and return($cb and $cb->($arg));

			if(!defined($w) and $! != EAGAIN and $! != EINTR){
				#this is actual error
				Log::OK::ERROR and log_error "SIO Writer: ERROR IN WRITE NO APPEND $!";
				#actual error		
				$_ww=undef;
				$wfh=undef;
				@queue=();	#reset queue for session reuse
				$on_error->($!);
				$cb->() if $cb;
				return;
			}

			push @queue,[$_[0], $offset, $cb, $arg];
			my $entry;
			$_ww = AE::io $wfh, 1, method {
				unless($wfh){
					Log::OK::ERROR and log_error "SIO Writer: file handle undef, but write watcher still active";
					return;
				}
				$entry=$queue[0];
				\my $buf=\$entry->[0];
				\my $offset=\$entry->[1];
				\my $cb=\$entry->[2];
				#\my $arg=\$entry->[3];
				$time=$clock;
				$offset+=$w = syswrite $wfh, $buf, length($buf)-$offset, $offset;
				if($offset==length $buf) {
					shift @queue;
					undef $_ww unless @queue;
					$cb->($entry->[3]) if $cb;
					return;
				}

				if(!defined($w) and $! != EAGAIN and $! != EINTR){
					#this is actual error
					Log::OK::ERROR and log_error "SIO Writer: ERROR IN WRITE $!";
					#actual error		
					$_ww=undef;
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
