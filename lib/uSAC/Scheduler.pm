package uSAC::Sheduler;

# Manages a schedualed list of jobs. Jobs are sorted by start time in the schedual
# Once the current time is triggers a job, it is added to the immediate queue, which is sorted by priority
# Lowest numerical priority ie exectued first 
#
# Periodic job 'templates' are kept seperate list, sorted by ID. A rendered version of the template is added ot the schedualled list once it is complete/failed.
#
use constant::more qw<
JOB_UNKOWN=0
JOB_ID
JOB_PRIORITY
JOB_NAME
JOB_STATE
JOB_RESULT

JOB_START
JOB_REPEAT
JOB_EXPIRY

JOB_ARGUMENT
JOB_WORK
JOB_TEMPLATE_ID
JOB_RETRY

>;
my %keys=(
  unkown      =>      JOG_UNKOWN,
  id          =>      JOB_ID,
  priority    =>      JOB_PRIORITY,
  name        =>      JOB_NAME,
  state       =>      JOB_STATE,
  result      =>      JOB_RESULT,
  argument    =>      JOB_ARGUMENT,
  work        =>      JOB_WORK,
  retry       =>      JOB_RETRY
);

constant::more  qw<
JOB_STATE_UNSCHEDUALED=0
JOB_STATE_PERIODIC
JOB_STATE_SCHEDUALED
JOB_STATE_IMMEDIATE
JOB_STATE_ACTIVE
JOB_STATE_FAILED
JOB_STATE_COMPLETE
>;

my $seq=0;
class uSAC::Sheduler;


field $_periodic;

# Sorted by start time
field $_schedualed

# Sorted by priority
field $_immediate;

# The worker pool
field $_pool;

# How many active jobs can be run concurrently
field $_concurrency;

# Known sub routines code refs
#
field $_rpc;

# Called when a worker processes has exited
#
field $_on_worker_complete;

# Called when a worker has finished the current RPC
field $_on_rpc_complete;

BUILD {
  $_on_worker_complete =sub {
     #
  };

  $_on_rpc_complete =sub {
  };

  # Create a pool with the RPC object
}
method create_job{
  my @job;

  if(int $_[0]){
    # Assume numerical keys
    for my($k, $v)(@_){
      $job[$k]=$v;
    }
  }
  else{
    #named keys
    for my($k, $v)(@_){
      $job[$keys{$k}]=$v;
    }
  }
  # Now we need to make a unique ID, have a sane priority and etc 

  $job[JOB_ID]=$seq++;
  $job[JOB_NAME]//="Job $seq";
  $job[JOB_REPEAT]//=0;
  $job[JOB_START]//=0;
  $job[JOB_RETRY]//=5;
  $job[JOB_RESULT]=undef;
  $job[JOB_PRIORITY]//=0;
  $job[JOB_STATE]//=JOB_STATE_UNQUEUED;



  \@job;
}

# Set the 
method schedual_job {
  my ($job, $start, $interval)=@_;
}

method cancel_job {

}

method status_job {

}

# Take a job and add it to the correct structures
method queue {

}

method start {
  # Any items in immedate queue are processed fifo as long as workers are available
  for my $job (@$_immediate){
    if(ref $job[JOB_WORK]){
      # Code reference, use pool directly. Check if we know it
      if(exists $_rpc->{$job[JOB_WORK]}}{
         # we know that workers running already  have this so get the next one
         $_pool->next_worker;
      }
      else {
        # No worker will have this. Mark all workers to be shutdown after current work
      }
    }
    else {
      # Command always fork a new process, save stdout as results
    }
  }
}

method pause {

}
1;
