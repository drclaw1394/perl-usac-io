use Object::Pad;
class uSAC::IO::AE::SWriter :isa(uSAC::IO::SWriter);

use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use uSAC::Log;
use Log::OK;
#use IO::FD::DWIM ":all";
use IO::FD;

use Errno qw(EAGAIN EINTR);
use parent "uSAC::IO::Writer";
use uSAC::IO::Writer qw<:fields>;

use constant::more RECUSITION_LIMIT=>5;
use constant::more DEBUG=>0;

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
method _make_writer :override {
	\my $wfh=$_wfh_ref;#\$self->wfh;	#refalias
	\my $on_error=\$self->on_error;#$_[3]//method{

	#\my $ww=\$self->[ww_];
	\my @queue=$self->queue;
	\my $time=$self->time;
	\my $clock=$self->clock;
  \my $syswrite=\$self->syswrite;
	my $w;
	my $offset=0;
	#Arguments are buffer and callback.
	#do not call again until callback is called
	#if no callback is provided, the session dropper is called.
	#
  #my $dummy_cb=sub { };
  my $entry;
  my $sub=sub {
        unless($wfh){
          DEBUG and Log::OK::TRACE and log_trace "SIO Writer: file handle undef, but write watcher still active";
          return;
        }
        $entry=$queue[0];
        \my $buf=\$entry->[0];
        \my $offset=\$entry->[1];
        \my $cb=\$entry->[2];

        #\my $arg=\$entry->[3];
        $time=$clock;
        #$offset+=$w = IO::FD::syswrite4 $wfh, $buf, length($buf)-$offset, $offset;
        $offset+=$w = $syswrite->( $wfh, $buf, length($buf)-$offset, $offset);
        if($offset==length $buf) {
          #Don't use the ref aliased vars here. not point to the correct thing?
          my $e=shift @queue;
          unless(@queue){
            undef $_ww ;
            $_recursion_counter=0;
          }
          #$e->[2]($e->[3]) if $e->[2];
          &{$e->[2]} if $e->[2];
        }
        elsif(!defined($w) and $! != EAGAIN and $! != EINTR){
          #this is actual error
          DEBUG and Log::OK::TRACE and log_trace "SIO Writer: ERROR IN WRITE $!";
          #actual error		
          $_ww=undef;
          $wfh=undef;
          @queue=();	#reset queue for session reuse
          $on_error and $on_error->($!);
          $cb and $cb->();
        }
      };

  sub {
    unless(@_ and $wfh){
      DEBUG and Log::OK::TRACE and log_trace "SIO: SWRITE reset stack called";
      $_recursion_counter=0;
      $_ww=undef;
      @queue=();
      return;
    }
    

    my $cb= $_[1];#//$dummy_cb;
    #my $arg=1;#$_[2]//__SUB__;			#is this method unless provided


    #Push to queue if watcher is active or need to do a async call
    if($_recursion_counter > RECUSITION_LIMIT or defined $_ww){
      push @queue, [$_[0][0], 0, $cb];
      #Watcher or queue active to ensure its running.
      ($_ww = AE::io($wfh, 1, $sub)) unless ($_ww and $wfh);
      return();
    }
    


    #Attempt to write immediately when no watcher no queued items
    $_recursion_counter++;
    $time=$clock;

    $w = $syswrite->($wfh, $_[0][0]);

    if( $w==length($_[0][0]) ){
      DEBUG and Log::OK::TRACE and log_trace "SWriter DID write all.. doing callback  length $w";
      $cb and &$cb;
    }
    elsif(!defined($w) and $! != EAGAIN and $! != EINTR){
      #this is actual error
      DEBUG and Log::OK::TRACE and log_trace "SIO Writer: ERROR IN WRITE NO APPEND $!";
      #actual error		
      $_ww=undef;
      $wfh=undef;
      @queue=();	#reset queue for session reuse
      $cb and $cb->();
      $on_error and $on_error->($!);
    }
    else {
      #The write did not send all the data. Queue it for async writing
      DEBUG and Log::OK::TRACE and log_trace "SWriter could not write all.. adding to queue";
      push @queue,[$_[0][0], $w, $cb];
      $_ww = AE::io $wfh, 1, $sub unless $_ww;
    }
    return ();
  };
}


method _make_reseter {
	\my @queue=$self->queue;
  sub {
      DEBUG and Log::OK::TRACE and log_trace "SIO: SWRITE reset stack called";
      $_recursion_counter=0;
      $_ww=undef;
      @queue=();
  }

}

1;
