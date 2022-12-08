use Object::Pad;
class uSAC::IO::AE::SWriter :isa(uSAC::IO::SWriter);
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use Log::ger;
use Log::OK;
#use IO::FD::DWIM ":all";
use IO::FD;

use Errno qw(EAGAIN EINTR);
use parent "uSAC::IO::Writer";
use uSAC::IO::Writer qw<:fields>;

use constant RECUSITION_LIMIT=>5;

field $_ww;		# Actual new variable for sub class
field $_wfh_ref;
field $_recursion_counter;

BUILD {
	$_wfh_ref=\$self->fh;
  $_recursion_counter=0;
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
  my $entry;
  my $sub=sub {
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
        $offset+=$w = IO::FD::syswrite4 $wfh, $buf, length($buf)-$offset, $offset;
        if($offset==length $buf) {
          #Don't use the ref aliased vars here. not point to the correct thing?
          my $e=shift @queue;
          unless(@queue){
            undef $_ww ;
            $_recursion_counter=0;
          }
          $e->[2]($e->[3]) if $e->[2];
        }
        elsif(!defined($w) and $! != EAGAIN and $! != EINTR){
          #this is actual error
          Log::OK::ERROR and log_error "SIO Writer: ERROR IN WRITE $!";
          #actual error		
          $_ww=undef;
          $wfh=undef;
          @queue=();	#reset queue for session reuse
          $on_error->($!);
          $cb->();
        }
      };

  sub {
    use integer;
    no warnings "recursion";
    #$wfh//$_[0]//return;				#undefined input. was a stack reset
    #my $dropper=$on_done;			#default callback

    unless(@_){
      #No arguments is classed as a stack reset
      @queue=();
      $_recursion_counter=0;
      $_ww=undef;
      return;
    }

    my $cb= $_[1];
    my $arg=1;#$_[2]//__SUB__;			#is this method unless provided

    $offset=0;				#offset allow no destructive
    #access to input
    #unless($wfh){
    #	Log::OK::ERROR and log_error "SIO Writer: file handle undef, but write called from". join ", ", caller;
    #	return;
    #}

    #Push to queue if watcher is active or need to do a async call
    #say "Recursion counter is $_recursion_counter";
    push @queue, [$_[0], 0, $cb, $arg] if($_recursion_counter>RECUSITION_LIMIT or $_ww);


    if(!$_ww and !@queue){
      #Attempt to write immediately when no watcher no queued items
      $_recursion_counter++;
      $time=$clock;
      $offset+=$w = IO::FD::syswrite2($wfh, $_[0]);

      if( $offset==length($_[0]) ){
        $cb and $cb->($arg)
      }
      elsif(!defined($w) and $! != EAGAIN and $! != EINTR){
        #this is actual error
        Log::OK::ERROR and log_error "SIO Writer: ERROR IN WRITE NO APPEND $!";
        #actual error		
        $_ww=undef;
        $wfh=undef;
        @queue=();	#reset queue for session reuse
        $cb->() if $cb;
        $on_error->($!);
      }
      else {
        #The write did not send all the data. Queue it for async writing
        push @queue,[$_[0], $offset, $cb, $arg];
        $_ww = AE::io $wfh, 1, $sub unless $_ww;
      }
    }
    else {
      #Watcher or queue active to ensure its running.
      $_ww = AE::io $wfh, 1, $sub unless $_ww;
    }
  };
}
1;
