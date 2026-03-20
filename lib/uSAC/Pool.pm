package uSAC::Pool;

use uSAC::IO;
use uSAC::FastPack::Broker;
use Data::FastPack;
use Object::Pad;
use Time::HiRes qw<time>;
use uSAC::Worker;
use feature "say";


class uSAC::Pool;

field $_available;
field $_in_use;
field $_broker;
field $_seq;
field $_procedures;
field $_workers;
field $_rr_index;

field $_queue;
field $_current_ids;        # hash of ids active and which worker it was sent to

field $_preload :param;            # Allocate and exece workers before jobs are availible
field $_min_size;           # Minimum number of workers to keep alive
field $_max_size;           # Max normal pool size

field $_rpc     :param = {}; # Shared RPC, This is passed to all worker constructors

BUILD {
  $_max_size//=4;
  $_in_use={};
  $_available=[];

  $_rr_index=0;
  $_seq=0;
  $_workers=[];
  
  use feature ":all";
  my @temp;
  for(1..$_preload){
	  my $w=$self->next_worker;
	  $w->shrink_mask=0;
	  say STDERR "preloaded worker is $w";
	  push @temp, $w;
	  delete $_in_use->{$w};
  }
  @$_available=@temp;
  say STDERR @temp;

  
}

method next_worker {

  my $urgent=shift;
  my $w=shift @$_available;
  unless(defined $w){
    # No available worker. Either make a new one or if limits reached
    # we queue in an already busy one
    
    if($urgent or (@$_workers < $_max_size)){
      # Make a new worker
      $w=uSAC::Worker->new(rpc=>$_rpc, work=>sub{}, on_complete=>sub{
          # Push back ti available
          #asay $STDERR, "-----WORKER PUSHED BACK----";
          #push @$_available, $w;
          #delete $_in_use->{$w};

        });
      push @$_workers, $w;
    }
    else {
      # Queue in existing busy
      $_rr_index++;
      if($_rr_index >= @$_workers){
        $_rr_index=0;
      }
      $w=$_workers->[$_rr_index]; 
    }
  }
  else {
    # existing. reuse
  }

  # Push the inuse 
  $_in_use->{$w}=1 if defined $w;

  #say STDERR "Next worker is $w with wid @{[$w->wid]} and bridge @{[$w->bridge]}";
  $w;
}

# Call a named / stored routine
method rpc {
  my ($name, $string, $cb, $error)=@_;
  #say STDERR "$$ AVAIBLABLE WORKER POOL @$_available";
  my $w=$self->next_worker;
  unless(defined $w){
    $error and $error->("Could not get worker");
    return;
  }

  $w->rpc($name, $string, sub {
		  #asay $STDERR, "RPC callback in pool";
      #asay $STDERR, Dumper @_;
      # REmove from the in_use
      delete $_in_use->{$w};
      # Add back to the live pool unless it is an urgent (more than max)
      push @$_available, $w;# if @$_available < $_max_size;


      # Execute client callback
      &$cb;
    },

    $error
  );
}

# Call an rpc on the same worker, even if it will causes a block
method sticky_rpc{
  my ($name, $string, $cb, $error, $wid)=@_;
  my $w;
  unless($wid){
    $w=$self->next_worker;
    # Sticky workers need to be closed directly
    $w->shrink_mask=0;
  }
  else{
    ($w)=grep {$wid eq $_->wid} @$_workers;
    #$w//=$_available->{$wid}||$_in_use->{$wid};

    # Perhaps worker died
    $w//=$self->next_worker;
  }

  $w->rpc($name, $string, sub {
		  #asay $STDERR, "RPC callback in pool";
      #asay $STDERR, Dumper @_;
      # REmove from the in_use
      delete $_in_use->{$w};
      # Add back to the live pool unless it is an urgent (more than max)
      push @$_available, $w;# if @$_available < $_max_size;

      # Help with stickyness. last arg is the worker id
      push @_, $wid;

      # Execute client callback
      &$cb;
    },

    $error
  );

  
}

# make a named sub. 
method add_rpc {
  my $name=shift;
  my $code=shift;
  $_rpc->{$name}=$code;
  
  #Need to mark all workers to be ended
}

method remove_rpc {
  my $name=shift;
  delete $_rpc->{$name};
}

# The c
method close {
	#asay $STDERR, "---CLOSING POOL----";
  for(@$_workers){
      $_->close;
  }
  @$_workers=();
  @$_available=();
}


1;
