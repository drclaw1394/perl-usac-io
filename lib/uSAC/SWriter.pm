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

use enum (qw<writer_ ctx_ on_eof_ on_error_ cancel_>);


sub new {
	my $package=shift//__PACKAGE__;
	my $self=&make_sio_writer;
	bless $self, $package;
}

sub writer {
	$_[0][writer_];
}

sub ctx : lvalue{
	$_[0][ctx_]->$*;
}

sub on_eof : lvalue {
	$_[0][on_eof_]->$*;
}

sub on_error : lvalue{
	$_[0][on_error_]->$*;
}

#methods

sub cancel {
	&{$_[0][cancel_]};
}

sub write {
	shift;
	&{$_[0][writer_]};
}

sub make_sio_writer {
	my $sub=sub{
		my $ctx=$_[0];
		my $wfh=$_[1];
		my $w_cb=$_[2];
		my $on_eof=$_[3]//sub{
			#print "Done\n";
			#close socket
		};
		my $on_error=$_[4]//sub{
			#close socket
			#print "Error\n";
		};
		#setup writer sub

		my $ww;
		my $w;
		my $wbuf;
		my $offset=0;
		my @queue;
		#Arguments are buffer and callback.
		#do not call again until callback is called
		#if no callback is provided, the session dropper is called.
		#
		my $writer=sub {
			use integer;
			$_[0]//return;				#undefined input. was a stack reset
			#my $dropper=$on_done;			#default callback

			my $cb= $_[1];#//$dropper;		#when no cb provided, use dropper
			my $arg=$_[2]//__SUB__;			#is this sub unless provided

			$offset=0;# if $pre_buffer!=$_[0];	#do offset reset if need beo
			#$pre_buffer=$_[0];
			#say "preview: ", substr($buf ,0 , 10),"length: ", length $_[0];
			if(!$ww){
				#no write watcher so try synchronous write
				$offset+=$w = syswrite($wfh, $_[0], length($_[0])-$offset, $offset);
				#$offset+=$w;
				say $! unless $w;
				if($offset==length $_[0]){
					#say "FULL WRITE NO APPEND";
					#say "writer cb is: $cb";
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
				#say "Watcher exists, pushing to queue+++";
				push @queue, [$_[0],0,$cb,$arg];
			}

		};
		#return a canceller
		return [$writer, \$ctx, \$on_eof, \$on_error, sub {undef $ww }];
	};
	&$sub;
}

1;
