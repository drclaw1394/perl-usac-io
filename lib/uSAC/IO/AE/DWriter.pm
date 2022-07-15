use Object::Pad;
package uSAC::IO::AE::DWriter;
class uSAC::IO::AE::DWriter :isa(uSAC::IO::DWriter);
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Log::ger;
use Log::OK;
use Errno qw(EAGAIN EINTR);
use constant DEBUG=>1;

field $_ww;
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
method _make_writer :override {
	say "IN AE::Dwriter make _writer". $self;
	#\my $ctx=\$self->[ctx_];#$_[0];
	\my $wfh=$_wfh_ref;#\$self->wfh;
	\my $on_error=\$self->on_error;

	#\my $ww=\$self->[ww_];
	\my @queue=$self->queue;
	\my $time=$self->time;
	\my $clock=$self->clock;

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
		my $to=$_[2];#//__SUB__;			#is this sub unless provided

		$offset=0;				#offset allow no destructive
		unless($wfh){
			Log::OK::ERROR and log_error "IO Writer: file handle undef, but write called from". join ", ", caller;
			return;
		}
							#access to input
		if(!$_ww){
			#no write watcher so try synchronous write
			$time=$clock;
			say "In write: ".unpack "H*", $to;
			say "In write: ".unpack "H*", getpeername $wfh;

			$offset+= $w= $to 
				? send $wfh, $_[0], $flags, $to
				: send $wfh, $_[0], $flags;
			$offset==length($_[0]) and return($cb and $cb->($to));

			#TODO: DO we need to restructure on ICMP results for a unreachable host, connection refused, etc?
			if(!defined($w) and $! != EAGAIN and $! != EINTR){
				#this is actual error
				warn $! if DEBUG;
				warn "ERRNO: ".($!+0);
				#actual error		
				$_ww=undef;
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
			push @queue,[$_[0], $offset, $cb, $to];
			#say "PARTIAL WRITE Synchronous";
			my $entry;
			$_ww = AE::io $wfh, 1, sub {
				$entry=$queue[0];
				\my $buf=\$entry->[0];
				\my $offset=\$entry->[1];
				\my $cb=\$entry->[2];
				\my $to=\$entry->[3];
				#say "watcher cb";
				$$time=$$clock;
				#$offset+=$w = syswrite $wfh, $buf, length($buf)-$offset, $offset;
				#$offset+= $w= send $wfh, substr($buf,$offset), $flags;
				$offset+= $w= $to 
					? send $wfh, substr($buf,$offset), $flags, $to
					: send $wfh, substr($buf,$offset), $flags;
				if($offset==length $buf) {
					#say "FULL async write";
					shift @queue;
					undef $_ww unless @queue;
					$cb->($to) if $cb;
					return;
				}

				if(!defined($w) and $! != EAGAIN and $! != EINTR){
					#this is actual error
					warn "ERROR IN EVENT WRITE" if DEBUG;
					warn $! if DEBUG;
					#actual error		
					$_ww=undef;
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
			push @queue, [$_[0],0,$cb,$to];
		}

	};
}

1;
