package uSAC::Scheduler;
use uSAC::IO;
use uSAC::Log;
use Log::OK;
use Object::Pad;

use List::Insertion {prefix=> "time",     type=>"numeric", duplicate=>"left", accessor=>'->[uSAC::Scheduler::JOB_START()]'};
use List::Insertion {prefix=> "priority", type=>"numeric", duplicate=>"left", accessor=>'->[uSAC::Scheduler::JOB_PRIORITY()]'};

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
JOB_DEPS
JOB_INFORM
JOB_PROCESS
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
  retry       =>      JOB_RETRY,
  deps        =>      JOB_DEPS
);



use constant::more  qw<
JOB_STATE_UNSCHEDUALED=0
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
      
      # Update job state to show it is in the immediate list
      #
      $job->[JOB_STATE]= JOB_STATE_IMMEDIATE;
      # Now insert using priority into immediate 
      if(@$_immediate){
        my $i=priority_numeric_left($job, $_immediate);
        splice @$_immediate, $i, 0, $job; 
      }
      else {
        push @$_immediate, $job;
      }
      #Log::OK::TRACE and log_trace 



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

      Log::OK::TRACE and log_trace "--about to do work $job->[JOB_WORK]";
      $_current_concurrency++;
      # Command always fork a new process, save stdout as results
      $job->[JOB_STATE]=JOB_STATE_ACTIVE;
      my $cb=sub {

        $_current_concurrency--;
        $job->[JOB_RESULT]=$_[0][2];
        print STDOUT "RESULT IS: $job->[JOB_RESULT] \n";

        # If the job is perioding, recalculate start and reinsert
        if($job->[JOB_TYPE]==JOB_TYPE_PERIODIC()){
          Log::OK::TRACE and log_trace "--PERIODIC job.. should we re schedual?";
          $job->[JOB_START]+=$job->[JOB_INTERVAL];
          $job->[JOB_START]=time if $job->[JOB_START] < time;


          # Check for expriy, to see if we actuall reinsert
          if($job->[JOB_EXPIRY]==0 or $job->[JOB_START] < $job->[JOB_EXPIRY]){
            Log::OK::TRACE and log_trace "--PERIODIC job.. re added";
            $self->schedual_job($job);
          }
          else {
            Log::OK::TRACE and log_trace "--PERIODIC job.. done";
            $job->[JOB_STATE]=JOB_STATE_COMPLETE;

          }
        }
        else {

          $job->[JOB_STATE]=JOB_STATE_COMPLETE;
        }


        # Job has results or otherwise failed, now look at informed jobs to potentially add them
        if($job->[JOB_STATE]==JOB_STATE_COMPLETE){
          for($job->[JOB_INFORM]->@*){
            Log::OK::TRACE and log_trace "------INFORMING  key $_";
            my $j=$_jobs->{$_};

            use Data::Dumper;
            Log::OK::TRACE and log_trace "------job is ".Dumper $j;
            if($j->[JOB_STATE]==JOB_STATE_SCHEDUALED){
              my $ready=1;

              for ($j->[JOB_DEPS]->@*){
                my $jj=$_jobs->{$_};
                Log::OK::TRACE and log_trace "------INFORMING $jj";
                $ready&&=($jj->[JOB_STATE]==JOB_STATE_COMPLETE);
              }

              if($ready){
                # Acutaly add to the time based schedual
                Log::OK::TRACE and log_trace "------ADDING NEW JOB";

                # Ensure a sane start time
                $j->[JOB_START]=time if $j->[JOB_START] < time;
                my $i;
                if(@$_schedualed){
                  $i=time_numeric_left($j, $_schedualed);
                  splice @$_schedualed, $i, 0, $j; 
                }
                else {
                  push @$_schedualed, $j;
                  $i=0;
                }
                Log::OK::TRACE and log_trace "found index at $i";
                if($i == @$_schedualed-1){
                  # added to the end, so recalculate timer
                  $self->_recalculate_timer;
                }
              }

            }
          }
        }

        #Log::OK::TRACE and log_trace "RESULTE FROM WORK: $job->[JOB_RESULT][0]";
        asap $_process_sub; # retrigger

        # broadcast the id of the job that finished

      };
      if(ref $job->[JOB_WORK]){
        my $w=uSAC::Worker->new(work=> $job->[JOB_WORK], on_complete=>$cb);
      }
      else {
        my $pid=backtick $job->[JOB_WORK], $cb;
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
  $job[JOB_PRIORITY]//=0;
  $job[JOB_DEPS]//=[];
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
  else{
    $job->[JOB_TYPE] = JOB_TYPE_SCHEDUALED;
  }

  # Expire the job after 2 days past start date if one hasn't been set
  $job->[JOB_EXPIRY]//=$job->[JOB_START]+3600*24*2; # Two days past

  
  # Check dep jobs actually exist, if the don't we fail to schedual at all
  #
  #$job->[JOB_DEPS]//=[];
  for($job->[JOB_DEPS]->@*){
    my $j=$_jobs->{$_};
    return undef unless defined $j;
    push $j->[JOB_INFORM]->@*, $job->[JOB_ID];
  }

  # Add the job to the job DB, keyed by id
  
  $job->[JOB_STATE]=JOB_STATE_SCHEDUALED;
  $_jobs->{$job->[JOB_ID]}=$job;

  return $job->[JOB_ID] if $job->[JOB_DEPS]->@*;


  my $i=-1;
  if($_schedualed->@* == 0) {
    push @$_schedualed, $job;
    $i=0;
  }
  else {
      # Now insert using priority into immediate 
      if(@$_schedualed){
        $i=time_numeric_left($job, $_schedualed);
        splice @$_schedualed, $i, 0, $job; 
      }
      else {
        push @$_schedualed, $job;
      }
      #$job->[JOB_STATE]=JOB_STATE_SCHEDUALED;
  }

  if($i == @$_schedualed-1){
    # added to the end, so recalculate timer
    $self->_recalculate_timer;
  }


  #Return the JOB ID
  $job->[JOB_ID];
}

method cancel_job {
  my $id=shift;
  my $job=delete $_jobs->{$id};

  return undef unless defined $job;


  for($job->[JOB_STATE]){
    if($_ == JOB_STATE_SCHEDUALED){
      # In the schedualed list. Find by start time   and remove
      my $i=time_numeric_left $job->[JOB_START], $_schedualed;
      
      # $i is left most index of duplicates.. so continue search upwards
      while($i < @$_schedualed){
        if($_schedualed->[$i][JOB_ID]==$job->[JOB_ID]){
          splice @$_schedualed, $i, 1; 
          last;
        }
        $i++;
      }
    }
    elsif($_ == JOB_STATE_IMMEDIATE){
      # In the schedualed list. Find by priority and remove
      my $i=priority_numeric_left $job->[JOB_PRIORITY], $_schedualed;

      # $i is left most index of duplicates.. so continue search upwards
      while($i < @$_schedualed){
        if($_schedualed->[$i][JOB_ID]==$job->[JOB_ID]){
          splice @$_schedualed, $i, 1; 
          last;
        }
        $i++;
      }
    }
    elsif($_ ==JOB_STATE_COMPLETE){
      # DO nothing.. aleady removed from hash
    }
    elsif($_ == JOB_STATE_ACTIVE){
      #sub_process_cancel
    }
  }

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

=head1 NAME

uSAC::Scheduler - Jobs on a schedule

=head1 DESCRIPTION


=head2 HOW IT WORKS

Jobs are added to a 'schedualed' list, which is storted by start time (unix
time). When the current time is larger or equal to the start time, the job is
shifted into the 'immediate' queue, which is sorted by priority. As existing
jobs finish, the new jobs are poped of the immedate list.

If an high priority job needed asap exectution, it would be scheduled with the
current time (or less) as the start time, and the large value for the priority.
This would force it to the front of the queue and then processed at the next
available chance.


