package uSAC::Scheduler;

use List::Insertion {prefix=> "time", type=>"numeric", duplicate=>"left", accessor=>'->[JOB_START]'};
use List::Insertion {prefix=> "priority", type=>"numeric", duplicate=>"left", accessor=>'->[JOB_PRIORITY]'};
use uSAC::IO;
use uSAC::Log;
use Log::OK;
use Object::Pad;

# Manages a schedualed list of jobs. Jobs are sorted by start time in the schedual
# Once the current time is triggers a job, it is added to the immediate queue, which is sorted by priority
# Lowest numerical priority ie exectued first 
#
# Periodic job 'templates' are kept seperate list, sorted by ID. A rendered version of the template is added ot the schedualled list once it is complete/failed.
#
#




use constant::more qw<
JOB_UNKOWN=0
JOB_ID
JOB_TYPE
JOB_PRIORITY
JOB_NAME
JOB_STATE
JOB_RESULT

JOB_START
JOB_INTERVAL
JOB_EXPIRY

JOB_ARGUMENT
JOB_WORK
JOB_TEMPLATE_ID
JOB_RETRY

>;

my %keys=(
  unkown      =>      JOG_UNKOWN,
  id          =>      JOB_ID,
  type        =>      JOB_TYPE,
  priority    =>      JOB_PRIORITY,
  name        =>      JOB_NAME,
  state       =>      JOB_STATE,
  result      =>      JOB_RESULT,
  start       =>      JOB_START,
  interval    =>      JOB_INTERVAL,
  expiry      =>      JOB_EXPIRY,
  argument    =>      JOB_ARGUMENT,
  work        =>      JOB_WORK,
  retry       =>      JOB_RETRY
);



use constant::more  qw<
JOB_STATE_UNSCHEDUALED=0
JOB_STATE_PERIODIC
JOB_STATE_SCHEDUALED
JOB_STATE_IMMEDIATE
JOB_STATE_ACTIVE
JOB_STATE_FAILED
JOB_STATE_COMPLETE
>;


use constant::more  qw<
  JOB_TYPE_SCHEDUALED=0
  JOB_TYPE_PERIODIC
>;

my $seq=0;




class uSAC::Scheduler;


field $_run;

# Hash of jobs keyed by id
#
field $_jobs; 

#
field $_periodic;

# Sorted by start time
field $_schedualed

# Sorted by priority
field $_immediate;

# The worker pool
field $_pool;

# How many active jobs can be run concurrently
field $_max_concurrency;

# Current number of jobs running
field $_current_concurrency;

# Known sub routines code refs
#
field $_rpc;

# Called when a worker processes has exited
#
field $_on_worker_complete;

# Called when a worker has finished the current RPC
field $_on_rpc_complete;


# This timer is calculated using the earlised item in the scheduld list When it
# triggers, it moves the this item to the immediate queue, and recalculates a
# new timer.
#
field $_schedual_timer;
field $_timer_sub;

field $_process_sub;

BUILD {
  $_schedualed=[];
  $_immediate=[];

  $_current_concurrency=0;
  $_max_concurrency=4;

  $_on_worker_complete =sub {
     #
  };

  $_on_rpc_complete =sub {
  };

  $_run=undef;

  # Executed when scheduled timer expires
  #
  $_timer_sub =sub {
    $_schedual_timer=undef;
    Log::OK::TRACE and log_trace "--timer sub top";
    # Take the first item from the schedualled list
    my $job=pop @$_schedualed;
    Log::OK::TRACE and log_trace " latest job is $job";
    if($job){

      # Now insert using priority into immediate 
      if(@$_immediate){
        my $i=priority_numeric_left($job, $_immediate);
        splice @$_immediate, $i, 0, $job; 
      }
      else {
        push @$_immediate, $job;
      }
      #Log::OK::TRACE and log_trace 



      # If the job is perioding, recalculate start and reinsert
      if($job->[JOB_TYPE]==JOB_TYPE_PERIODIC()){
        Log::OK::TRACE and log_trace "--PERIODIC job.. should we re schedual?";
        $job->[JOB_START]+=$job->[JOB_INTERVAL];
        $job->[JOB_START]=time if $job->[JOB_START] < time;
        Log::OK::TRACE and log_trace "Start    $job->[JOB_START]";
        Log::OK::TRACE and log_trace "interval $job->[JOB_INTERVAL]";
        Log::OK::TRACE and log_trace "expiry   $job->[JOB_EXPIRY]";
        Log::OK::TRACE and log_trace "time     @{[ time ]}";

        
        # Check for expriy, to see if we actuall reinsert
        if($job->[JOB_EXPIRY]==0 or $job->[JOB_START] < $job->[JOB_EXPIRY]){
          Log::OK::TRACE and log_trace "--PERIODIC job.. re added";
          $self->schedual_job($job);
        }
        else {
          Log::OK::TRACE and log_trace "--PERIODIC job.. done";

        }
      }
      $self->_recalculate_timer;
      $_process_sub->();
    }
    else {
      # NO jobs... so nothing to do
    }
    


  };


  # Execute when a sub process is complete, or is available
  $_process_sub=sub {
    Log::OK::TRACE and log_trace "--Top of process sub";
    
    while($_run and @$_immediate and $_current_concurrency < $_max_concurrency){
      Log::OK::TRACE and log_trace "Run is $_run and concurrency is $_current_concurrency    max is $_max_concurrency";
      # Any items in immedate queue are processed fifo as long as workers are available
      my $job= pop @$_immediate;

      if(ref $job->[JOB_WORK]){
        # Code reference, use pool directly. Check if we know it
        if(exists $_rpc->{$job->[JOB_WORK]}){
          # we know that workers running already  have this so get the next one
          $_pool->next_worker;
        }
        else {
          # No worker will have this. Mark all workers to be shutdown after current work
        }
      }
      else {
        Log::OK::TRACE and log_trace "--about to do work $job->[JOB_WORK]";
        $_current_concurrency++;
        # Command always fork a new process, save stdout as results
        backtick $job->[JOB_WORK], sub {

          $_current_concurrency--;
          $job->[JOB_RESULT]=$_[0];

          #Log::OK::TRACE and log_trace "RESULTE FROM WORK: $job->[JOB_RESULT][0]";
          asap $_process_sub; # retrigger

          # broadcast the id of the job that finished

        };
      }

    }

  };

}

method _recalculate_timer {
  Log::OK::TRACE and log_trace "Recalculating timer";
  # Recalcualte timer to trigger at the relative time to next job
  my $next=$_schedualed->[-1];

  Log::OK::TRACE and log_trace  "Next is $next"; 
  if($next){
    my $rel=$next->[JOB_START]-time;
    Log::OK::TRACE and log_trace  "creating timer with a value of $rel";
    timer_cancel $_schedual_timer;
    $_schedual_timer=timer $rel, 0, $_timer_sub;
  }
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

  $job[JOB_NAME]//="Job $seq";
  $job[JOB_INTERVAL]//=0;
  $job[JOB_START]//=time;
  $job[JOB_RETRY]//=5;
  $job[JOB_RESULT]=undef;
  #$job[JOB_EXPIRY]=0;
  $job[JOB_PRIORITY]//=10;
  $job[JOB_STATE]//=JOB_STATE_UNSCHEDUALED;




  \@job;
}

# Set the 
method schedual_job {
  # Adds the job to the schedualled queue, by inserting into the correct position
  # Recalculates a timer to trigger moving the head if the insertion point is the last item
  #
  

  
  my ($job)=@_;

  # Ensure id is set
  $job->[JOB_ID]=$seq++;

  if($job->[JOB_INTERVAL] > 0){
    $job->[JOB_TYPE] = JOB_TYPE_PERIODIC;
  }

  # Expire the job after 2 days past start date if one hasn't been set
  $job->[JOB_EXPIRY]//=$job->[JOB_START]+3600*24*2; # Two days past

  
  my $i=-1;
  if($_schedualed->@* == 0) {
    push @$_schedualed, $job;
    $i=0;
  }
  else {
      # Now insert using priority into immediate 
      if(@$_schedualed){
        $i=priority_numeric_left($job, $_schedualed);
        splice @$_schedualed, $i, 0, $job; 
      }
      else {
        push @$_schedualed, $job;
      }
    $job->[JOB_STATE]=JOB_STATE_SCHEDUALED;
  }

  if($i == @$_schedualed-1){
    # added to the end, so recalculate timer
    $self->_recalculate_timer;
  }

  #Return the JOB ID
  $job->[JOB_ID];
}

method cancel_job {

}


method status_job {
  my $id=shift;
  my $job=$_jobs->{$id};

  if($job){
    return $job->[JOB_STATE];
  }
}


# Enables event and timer processing. Run the jobs
method start  {
  $_run=1;
  $self->_recalculate_timer;
  $_process_sub->();
}


method pause {
  # cancel the timer if it is active. and block the immediate sub from running
  cancel_timer($_schedual_timer);
  $_run=0;
}

1;
