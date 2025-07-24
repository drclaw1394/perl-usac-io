use Object::Pad;
class uSAC::IO::AE::SWriter :isa(uSAC::IO::SWriter);

use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;

use AnyEvent;
use uSAC::Log;
use Log::OK;
use IO::FD;

use Errno qw(EAGAIN EINTR);
use parent "uSAC::IO::Writer";
use uSAC::IO::Writer qw<:fields>;

use constant::more RECUSITION_LIMIT=>10;
use constant::more DEBUG=>0;

field $_ww;		# Actual new variable for sub class
field $_wfh;
field $_recursion_counter;
field $_writer;
field $_resetter;

BUILD {
	$_wfh=$self->fh;
  $_recursion_counter=0;
  $_writer=$self->_make_writer;
  $_resetter=$self->_make_reseter;
}

method set_write_handle :override ($wh){
  $self->fh=$wh;
  $_wfh=$wh;
	$_ww=undef;
  $_writer=undef;
  $_writer=$self->_make_writer;
}

#pause any automatic writing
method pause :override {
	$_ww=undef;
	$self;
}
method reset :override {
  &{$_resetter};
}

method write :override{
	&{$_writer};
}
method writer :override {
  $_writer;
}

#internal
#Aliases variables for (hopefully) faster access in repeated calls
method _make_writer :override {
  #\my $on_error=\$self->on_error;

	#\my $ww=\$self->[ww_];
	my $queue=$self->queue;
	my $time=$self->time;
	my $clock=$self->clock;
  my $syswrite=$self->syswrite;
	my $w;
	my $offset=0;
	#Arguments are buffer and callback.
	#do not call again until callback is called
	#if no callback is provided, the session dropper is called.
	#
  #my $dummy_cb=sub { };
  my $entry;
  my $sub=sub {
      use feature "try";
        try {
        unless($_wfh){
          DEBUG and Log::OK::TRACE and log_trace "SIO Writer: file handle undef, but write watcher still active";
          return;
        }
        $entry=$queue->[0];
        \my $buf=\$entry->[0];
        \my $offset=\$entry->[1];
        \my $cb=\$entry->[2];

        $$time=$$clock;
        $offset+=$w = $syswrite->( $_wfh, $buf, length($buf)-$offset, $offset);
        if($offset==length $buf) {
          #Don't use the ref aliased vars here. not point to the correct thing?
          my $e=shift @$queue;
          unless(@$queue){
            undef $_ww ;
            $_recursion_counter=0;
          }
          #$e->[2]($e->[3]) if $e->[2];
          &{$e->[2]} if $e->[2];
          $e->[2]=undef if $e->[2];
          DEBUG and print STDERR "SWRITE callback from quque\n";
          @$e=();
          $buf=undef;
        }
        elsif(!defined($w) and $! != EAGAIN and $! != EINTR){
          #this is actual error
          DEBUG and Log::OK::TRACE and log_trace "SIO Writer: ERROR IN WRITE $!";
          #actual error		
          $_ww=undef;
          #$_wfh=undef;
          @$queue=();	#reset queue for session reuse
	        my $on_error=$self->on_error;
          $on_error and $on_error->($!);
          #$cb and $cb->();
        }
      }
      catch($e){
        uSAC::IO::AE::IO::_exception($e);
      }
      };

  sub {
    unless(@_ and $_wfh){
      DEBUG and Log::OK::TRACE and log_trace "SIO: SWRITE reset stack called";
      $_recursion_counter=0;
      $_ww=undef;
      @$queue=();
      return;
    }
    

    my $cb= $_[1];#//$dummy_cb;
    #my $arg=1;#$_[2]//__SUB__;			#is this method unless provided


    #Push to queue if watcher is active or need to do a async call
    if($_recursion_counter > RECUSITION_LIMIT or defined $_ww){
      DEBUG and print STDERR "SWriter water exists for fd $_wfh. Pushing to queue\n";
      push @$queue, [$_[0][0], 0, $cb];
      $_[0][0]=undef;
      $cb=undef;
      $_recursion_counter=0;
      #Watcher or queue active to ensure its running.
      ($_ww = AE::io($_wfh, 1, $sub)) unless ($_ww and $_wfh);
      return();
    }
    


    #Attempt to write immediately when no watcher no queued items
    $_recursion_counter++;
    $$time=$$clock;

    $w = $syswrite->($_wfh, $_[0][0]);

    DEBUG and print STDERR "WRITE $w bytes out of ". length $_[0][0];

    if( $w==length($_[0][0]) ){
      #DEBUG and Log::OK::TRACE and log_trace unpack "H*",$_[0][0] if $w<100;
      DEBUG and print STDERR "SWriter DID write all.. doing callback  length $w\n";
      #DEBUG and Log::OK::TRACE and log_trace "QUEUE length is: @queue";
      $_[0][0]=undef;
      $cb and &$cb;
      $cb=undef;
    }
    elsif(!defined($w) and $! != EAGAIN and $! != EINTR){
      #this is actual error
      DEBUG and print STDERR "SIO Writer: ERROR IN WRITE NO APPEND $!\n";
      #actual error		
      $_ww=undef;
      #$_wfh=undef;
      @$queue=();	#reset queue for session reuse

      #$_[0][0]=undef;
      #$cb and $cb->();
      $cb=undef;

	    my $on_error=$self->on_error;
      $on_error and $on_error->($!);
    }
    else {
      #The write did not send all the data. Queue it for async writing
      DEBUG and print STDERR "SWriter could not write all.. adding to queue\n";
      push @$queue,[$_[0][0], $w, $cb];
      $cb=undef;
      $_[0][0]=undef;
      $_ww = AE::io $_wfh, 1, $sub unless $_ww;
    }
    return ();
  };
}


method _make_reseter {
	my $queue=$self->queue;
  sub {
      DEBUG and Log::OK::TRACE and log_trace "SIO: SWRITE reset stack called";
      $_recursion_counter=0;
      $_ww=undef;
      for(@$queue){
        #$_->[0]=undef
        $_->[2]=undef;
      }
      @$queue=();
  }

}

####################################
# method _make_destroy {           #
#         \my @queue=$self->queue; #
#   sub {                          #
#   # Destroy the queue            #
#       for(@queue){               #
#         $_->[2]=undef;           #
#       }                          #
#       @queue=();                 #
#   # Undef subs                   #
#   $ww=undef;                     #
#                                  #
#   }                              #
# }                                #
####################################
method destroy :override {
  Log::OK::TRACE and log_trace "--------DESTROY  in AE::SWriter\n";
  $self->SUPER::destroy();
  $_ww=undef;
  $_writer=undef;
  $_resetter=undef;
}


1;
