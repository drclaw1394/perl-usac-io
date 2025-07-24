package uSAC::Pool;

use uSAC::IO;
use uSAC::FastPack::Broker;
use Data::FastPack;
use Object::Pad;
use Time::HiRes qw<time>;
use uSAC::Worker;
use Data::Dumper;


class uSAC::Pool;

field $_available;
field $_in_use;
field $_broker;
field $_seq;
field $_procedures;
field $_workers;

field $_queue;
field $_current_ids;        # hash of ids active and which worker it was sent to

field $_preload;            # Allocate and exece workers before jobs are availible
field $_min_size;           # Minimum number of workers to keep alive
field $_max_size;           # Max normal pool size

field $_rpc     :param = {}; # Shared RPC, This is passed to all worker constructors

BUILD {
  $_max_size//=4;
  $_in_use={};
  $_available=[];

  $_seq=0;
  $_workers=[];
  
  
}

method next_worker {

  my $urgent=shift;
  my $w=shift @$_available;
  unless(defined $w){
    # No available worker 
    if($urgent or (@$_workers < $_max_size)){
      $w=uSAC::Worker->new(rpc=>$_rpc, on_complete=>sub{
          # Push back ti available
          push @$_available, $w;
          delete $_in_use->{$w};

        });
      push @$_workers, $w;
    }
  }
  else {
    # existing. reuse
  }

  # Push the inuse 
  $_in_use->{$w}=1 if defined $w;

  $w;
}

# Call a named / stored routine
method rpc {
  my ($name, $string, $cb, $error)=@_;
  my $w=$self->next_worker;
  asay $STDERR , "-=-=-=-==-=-=-=next worker is $w";
  $w->rpc($name, $string, sub {
      #asay $STDERR, "RPC callback in pool";
      #asay $STDERR, Dumper @_;
      # REmove from the in_use
      delete $_in_use->{$w};
      # Add back to the live pool unless it is an urgent (more than max)
      push @$_available, $w if @$_available < $_max_size;


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

method close {
  for(@$_workers){
      $_->close;
  }
}


1;
