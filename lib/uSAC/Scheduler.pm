package uSAC::Scheduler;

#use Time::HiRes qw<time>;
use uSAC::IO;
use uSAC::Log;
use Log::OK;
use BSD::Resource;
use Object::Pad;
use UUID qw<uuid4>;

use Export::These qw<create_job sequence_jobs>;
use List::Insertion {prefix=> "time",     type=>"numeric", duplicate=>"left", accessor=>'->[JOB_START()]'};

use List::Insertion {prefix=> "time",     type=>"numeric", duplicate=>"right", accessor=>'->[JOB_START()]'};

use List::Insertion {prefix=> "priority", type=>"numeric", duplicate=>"left", accessor=>'->[JOB_PRIORITY()]'};

# Manages a schedualed list of jobs. Jobs are sorted by start time in the schedual
# Once the current time is triggers a job, it is added to the immediate queue, which is sorted by priority
# Lowest numerical priority ie exectued first 
#
# Periodic job 'templates' are kept in seperate list, sorted by ID. A rendered
# version of the template is added ot the schedualled list once it is
# complete/failed.
#
#


use constant::more DEBUG=>1;


use constant::more qw<
JOB_UNKOWN=0
JOB_ID
JOB_SCHEDUAL
JOB_PRIORITY
JOB_NAME
JOB_STATE
JOB_RESULT
JOB_TYPE
JOB_PARENT

JOB_GROUP_START
JOB_GROUP_END

JOB_START
JOB_ACTUAL_START
JOB_ACTUAL_FINISH

JOB_INTERVAL
JOB_DELAY
JOB_EXPIRY

JOB_ARGUMENT
JOB_WORK
JOB_TEMPLATE_ID
JOB_RETRY
JOB_DEPS
JOB_INFORM
JOB_PROCESS
JOB_ON_COMPLETE
JOB_ON_EXPIRE
JOB_ON_SCHEDUAL
JOB_ON_STATUS
JOB_ON_START
JOB_ATTEMPT
>;

my %keys=(
  unkown      =>      JOG_UNKOWN,
  id          =>      JOB_ID,
  schedual    =>      JOB_SCHEDUAL,
  priority    =>      JOB_PRIORITY,
  type        =>      JOB_TYPE,
  name        =>      JOB_NAME,
  state       =>      JOB_STATE,
  on_result   =>      JOB_RESULT, # Can be a callback to stream the results as the come
  on_complete =>      JOB_ON_COMPLETE,     # Called when the job is complete
  on_expire   =>      JOB_ON_EXPIRE,
  on_status   =>      JOB_ON_STATUS, # Status if a worker is used
  on_start    =>      JOB_ON_START, # Status if a worker is used
  on_schedual =>      JOB_ON_SCHEDUAL, # Called just before scheduallingof the job
                                      # this where sub jobs should be added

  start       =>      JOB_START,
  interval    =>      JOB_INTERVAL,
  delay       =>      JOB_DELAY,
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
JOB_STATE_ERROR
>;


use constant::more  qw<
  JOB_SCHEDUAL_SCHEDUALED=0
  JOB_SCHEDUAL_PERIODIC
>;


my $seq=0;




class uSAC::Scheduler;


field $_run;

# Hash of jobs keyed by id
#
field $_jobs; 

# Sorted by increasing start time
# Items are consumed by shifting and using the first item in the queue
# Duplicate start times are added 'to the right' so is a fifo for jobs
#
field $_schedualed

# Sorted by increasing priority
# Items are consumed by popping the queue.
# Duplicate priorities are added  'to the left' so jobs are fifo
#
field $_immediate;

# Failed jobs
#field $_failed;

# back off
#field $_backoff;

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
field $_next_start_time;

field $_process_sub;


# Persitant storage hooks
#
field $_on_immediate_drained :mutator;    # Called when immediate cache is  drained.
field $_on_schedualed_drained :mutator;    # Called when immediate cache is  drained.
                                 # Allows persitent storage of immediate jobs

field $_on_system_pressure_check :mutator;  #A callback which returns true if a job can be run. and false if no more jobs should be run currently


BUILD {
  $_schedualed=[];
  $_immediate=[];
  $_next_start_time=0;

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
    DEBUG and asay $STDERR, "--timer sub top";
    # Take the first item from the schedualled list
    my $job=shift @$_schedualed;
    DEBUG and adump $STDERR, " latest job is ", $job->[JOB_NAME];
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
    DEBUG and asay $STDERR, "--Top of process sub";
    
    asay $STDERR, "size of immediate: ".@$_immediate;
    asay $STDERR, "run of ",$_run;
    while($_run and @$_immediate and $_current_concurrency < $_max_concurrency){
      DEBUG and asay $STDERR, "Run is $_run and concurrency is $_current_concurrency    max is $_max_concurrency";
      # Any items in immedate queue are processed fifo as long as workers are available
      my $job= pop @$_immediate;

      DEBUG and asay $STDERR, "--about to do work $job->[JOB_WORK]";
      $_current_concurrency++;
      # Command always fork a new process, save stdout as results
      $job->[JOB_STATE]=JOB_STATE_ACTIVE;

      my $cb=sub {

        DEBUG and asay $STDERR, " --- In job callack";
        my $details=shift;
        #Log::OK::TRACE and log_trace "---RETURN DETAILS: ".Dumper $details;
        $_current_concurrency--;

        # Check the result code 
        if($details->[0] != 0){
          # Non zero return from process.. so assumed failure
          #
          $job->[JOB_STATE]=JOB_STATE_FAILED;

          DEBUG and asay $STDERR, " --- Job failed";
          # If we are allowed to retry...reschedual
          if($job->[JOB_RETRY]){
            # Re calculate start time if reties still available
            my $back_off=(3600*24*2)**(1/$job->[JOB_RETRY]);#10;#$self->backoff_time();
            $job->[JOB_START]=time+$back_off;
            $job->[JOB_RETRY]--;
            $self->_schedual($job);

          }
        }
        else {
          # Zero return from process.. so assumed success
          #




          # SET result if this was an accumulated raw output (ie from backticK)
          #$job->[JOB_RESULT]=$details->[2] if $details->[2];

          #print STDOUT "RESULT IS: $job->[JOB_RESULT] \n";
          #$job->[JOB_ON_COMPLETE] and asap sub {$job->[JOB_ON_COMPLETE]->($job->[JOB_RESULT])};
          $job->[JOB_ACTUAL_FINISH]=time;
          $job->[JOB_ON_COMPLETE] and $job->[JOB_ON_COMPLETE]->($details);#$job->[JOB_RESULT])};

          # If the job is perioding, recalculate start and reinsert
          if($job->[JOB_SCHEDUAL]==JOB_SCHEDUAL_PERIODIC()){
            DEBUG and asay $STDERR, "--PERIODIC job.. should we re schedual?";
            my $new_job=[@$job];

            $new_job->[JOB_START]+=$new_job->[JOB_INTERVAL];
            $new_job->[JOB_START]=time if $new_job->[JOB_START] < time;


            # Check for expriy, to see if we actuall reinsert
            if($new_job->[JOB_EXPIRY]==0 or $new_job->[JOB_START] < $new_job->[JOB_EXPIRY]){
              DEBUG and asay $STDERR, "--PERIODIC job.. re added";

              $new_job->[JOB_ID]=uuid4; #// Give a new id NOTE: need to fix deps of repeat
              $new_job->[JOB_DEPS]=[]; 
              $new_job->[JOB_INFORM]=[]; 
              $self->schedual_jobs($new_job);
            }
            else {
              DEBUG and asay $STDERR, "--PERIODIC job.. done";
              $new_job->[JOB_ON_EXPIRE] and $new_job->[JOB_ON_EXPIRE]->($new_job);
              #$job->[JOB_STATE]=JOB_STATE_COMPLETE;

            }
          }
          else {
            asay $STDERR, "+++++++ single shot job";
          }

            $job->[JOB_STATE]=JOB_STATE_COMPLETE;


          # Job has results or otherwise failed, now look at informed jobs to potentially add them
          if($job->[JOB_STATE]==JOB_STATE_COMPLETE){
            asay $STDERR, "_+_+_+_+_+ JOB COMPLETE";
            $self->_schedual_upstream($job);
          }
        }

        #Log::OK::TRACE and log_trace "RESULTE FROM WORK: $job->[JOB_RESULT][0]";
        asap $_process_sub; # retrigger

        # broadcast the id of the job that finished

      };


      # actual start
      $job->[JOB_ACTUAL_START]=time;
      $job->[JOB_ON_START] and $job->[JOB_ON_START]->($job);



      # Attemp to run another process to do the work
     
      if(ref($job->[JOB_WORK]) eq "CODE" ){
        my $w=uSAC::Worker->new(work=> $job->[JOB_WORK], on_complete=>$cb, on_status=>$job->[JOB_ON_STATUS], on_result=>sub { 
              my $v=$_[0];
              $job->[JOB_RESULT]->($v);
          },

        on_child=>sub {
          # This is hard sleep... this happens after fork, but before exec or
          # running worker code
          sleep $job->[JOB_DELAY] if $job->[JOB_DELAY];
        });

        # Save the worker in job entry
        $job->[JOB_PROCESS]=$w;
      }
      elsif(ref($job->[JOB_WORK]) eq "ARRAY" ){
        # array of children job ids
        #
        # make sub jobs deps of this job.?
        #push $job->[JOB_DEPS]->@*, $job->[JOB_WORK]->@*;

        # This is a group group job. schedual the group members
        for($job->[JOB_WORK]->@*){

          $self->schedual_jobs($_);
          $_->[JOB_PARENT]=$job->[JOB_ID];
        }
      }
      else {
        backtick $job->[JOB_WORK],  #Work
        sub {           # ON start
          # Onstart
          my $pid=shift;
          # Not a woker, but we save the PID
          $job->[JOB_PROCESS]=$pid;

        },
        $cb,        # On complete
        $job->[JOB_RESULT],      # on result (accumulated stdout)
        $job->[JOB_ON_STATUS]       # streaming onstatus (stderr)
      }

    }

  };

}

method _recalculate_timer {
  DEBUG and  asay $STDERR, "Recalculating timer";
  # Recalcualte timer to trigger at the relative time to next job
  my $next=$_schedualed->[0];

  DEBUG and asay $STDERR, "Time now is ", time;
  DEBUG and  asay $STDERR, "top  job is : $next";
  if($next ){
    DEBUG and asay $STDERR, "Start time of job is $next->[JOB_START]";
    #and $next->[JOB_START] != $_next_start_time){
    #$_next_start_time=$next->[JOB_START];
    # only create 
    my $rel=$next->[JOB_START]-time;
    $rel=0 if $rel<0;
    DEBUG and asay $STDERR, "creating timer with a value of $rel";
    timer_cancel $_schedual_timer;
    $_schedual_timer=timer $rel, 0, $_timer_sub;
  }
  else {
    #$_schedual_timer=timer 1, 0, sub { asay $STDERR, "DUMMPY SUB"};

  }
}


# Take a list of jobs and make each subsequent one depend on the
# previous in the list.
# 
# By defult jobs will be only according to start time. Multiple could run at the same time
#
# Using this guarentees the running order

sub sequence_jobs{
  my $prev=$_[0];
  my $i=0;
  for(@_){
    next unless $i++;
    push $_->[JOB_DEPS]->@*, $prev->[JOB_ID];
  }
}

sub create_job{
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

  $job[JOB_ID]//=uuid4;
  $job[JOB_NAME]//="Job $seq";
  $job[JOB_INTERVAL]//=0;
  $job[JOB_START]//=0;        #If no start time given. do it asap!
  $job[JOB_DELAY]//=0;
  $job[JOB_RETRY]//=5;
  #$job[JOB_EXPIRY]=0;
  $job[JOB_PRIORITY]//=0;
  $job[JOB_DEPS]//=[];
  $job[JOB_STATE]//=JOB_STATE_UNSCHEDUALED;
  $job[JOB_RESULT]//="";
  for($job[JOB_ON_SCHEDUAL]){
    if(! ref ){
      $_=eval "$_";
    }
  }

  \@job;
}


# Finds insert point in schedual queue.  Inserts job recalcuate schedual timer
# if is first item in quque
#
method _schedual {
  my $job=shift;
  my $i=-1;

  $job->[JOB_STATE]=JOB_STATE_SCHEDUALED;
  $job->[JOB_START]=time if $job->[JOB_START] < time;

  if($_schedualed->@* == 0) {
    push @$_schedualed, $job;
    $i=0;
  }
  else {
      # Now insert using priority into immediate 
      #if(@$_schedualed){
        $i=time_numeric_right($job, $_schedualed);
        splice @$_schedualed, $i, 0, $job; 
        #}
      #else {
      #  push @$_schedualed, $job;
      #  }
  }

  if($i == 0){
    # added to the start, so recalculate timer
    $self->_recalculate_timer;
  }

}

# Set the 
method schedual_jobs {
  # Adds the job to the schedualled queue, by inserting into the correct position
  # Recalculates a timer to trigger moving the head if the insertion point is the last item
  #
  # Does on_schedual callback to allow a job to setup sub jobs and deps


  my @ids;

  for my ($job)(@_){

    # Allow job to setup sub jobs. Done here for perioding jobs
    # The callback must set the deps of the job if it creates any sub jobs
    my @d;
    $job->[JOB_ON_SCHEDUAL] and @d=$job->[JOB_ON_SCHEDUAL]->($job);
    adump $STDERR, "DEPS before", $job->[JOB_DEPS];
    push $job->[JOB_DEPS]->@*, @d;
    adump $STDERR, "DEPS after", $job->[JOB_DEPS];




    # If job already exists. die
    die "Job does not have an ID $job->[JOB_ID]" unless defined $job->[JOB_ID];

    die "Job already exists $job->[JOB_ID]" if exists $_jobs->{$job->[JOB_ID]};

    # Ensure id is set
    #$job->[JOB_ID]=$seq++;

    if($job->[JOB_INTERVAL] > 0){
      $job->[JOB_SCHEDUAL] = JOB_SCHEDUAL_PERIODIC;
    }
    else{
      $job->[JOB_SCHEDUAL] = JOB_SCHEDUAL_SCHEDUALED;
    }

    # Expire the job after 2 days past start date if one hasn't been set
    $job->[JOB_EXPIRY]//=$job->[JOB_START]+3600*24*2; # Two days past


    # Add the job to the job DB, keyed by id

    $_jobs->{$job->[JOB_ID]}=$job;
     push @ids, $job->[JOB_ID];


    # Check dep jobs actually exist, if the don't we fail to schedual at all
    #
    $job->[JOB_DEPS]//=[];


    
    if($job->[JOB_DEPS]->@*){
      # Jobs with deps are not schedualed here
      my $all=0;
      for($job->[JOB_DEPS]->@*){
        my $j=$_jobs->{$_};
        last unless $j;
        $all++;
      }

      if($all != $job->[JOB_DEPS]->@*){
        adump $STDERR, "ADDING JOB, unmet deps. job added by not schedualled", $job;
        # Job gets added but is immediate fail. deps not met
        #$job->[JOB_STATE]=JOB_STATE_FAILED;
      }
      else {
        asay $STDERR, "ADDING JOB OK, met deps";
        # Deps all exist. Let them know they need to inform this new job when commplete
        #$job->[JOB_STATE]=JOB_STATE_SCHEDUALED;
        for($job->[JOB_DEPS]->@*){
          my $j=$_jobs->{$_};
          push $j->[JOB_INFORM]->@*, $job->[JOB_ID];
        }
        # if the dep job is completed before adding the inform.. we need to
        # trigger manually
        my $ready=$self->_check_deps_status($job);
        if($ready){
          $self->_schedual($job);

        }
      }
    }
    else {
      # Jobs without deps are scheduled here
      $self->_schedual($job);
    }


    #############################################################
    # # If we have deps we don't schedual... we wait for inform #
    # if( $job->[JOB_DEPS]->@*){                                #
    #  next;                                                    #
    # }                                                         #
    # else {                                                    #
    #   # ONLY SCHEDUAL IF NO DEPS                              #
    #   $self->_schedual($job);                                 #
    # }                                                         #
    #############################################################
  }
  return @ids;
}

# Returns true if a job has all deps are met and complete
method _check_deps_status {
  my $job=shift;

  return undef unless $job;

  my $ready=1;
  for ($job->[JOB_DEPS]->@*){
    my $jj=$_jobs->{$_};
    DEBUG and asay $STDERR, "------inspecting status of job $jj";
    $ready&&=($jj->[JOB_STATE]==JOB_STATE_COMPLETE);
  }
  $ready;
}

method _check_sub_status {
  my $job=shift;

  return undef unless $job;

  my $ready=1;
  my $ok=1;
  for ($job->[JOB_WORK]->@*){
    my $jj=$_jobs->{$_->[JOB_ID]};
    DEBUG and asay $STDERR, "------inspecting status of sub job $jj";
    $ready&&=($jj->[JOB_STATE]==JOB_STATE_COMPLETE);
    $ok&&=($jj->[JOB_STATE]==JOB_STATE_FAILED);
  }

  if($ready){
    # do call backs!
    $job->[JOB_STATE]=JOB_STATE_COMPLETE;
    $job->[JOB_ON_COMPLETE] and $job->[JOB_ON_COMPLETE]->([0]);
  }
  elsif(!$ok){
    $job->[JOB_STATE]=JOB_STATE_FAILED;
    #$job->[JOB_ON_] and $job-[JOB_ON_COMPLETE]->([]);
  }

}



# Takes a job, checks if it is complete If complete it informs all
# upstream/inform jobs to check if deps are ready
#
method _schedual_upstream{
  my $job=shift;
  return undef unless $job;

  if($job->[JOB_STATE] == JOB_STATE_COMPLETE) {

    for($job->[JOB_INFORM]->@*){
      my $j=$_jobs->{$_};
      my $ready=$self->_check_deps_status($j);
        if($ready){
          # Acutaly add to the time based schedual
          $self->_schedual($j);
        }
    }

    for($job->[JOB_PARENT]//()){
      my $j=$_jobs->{$_};
      # let parent know sub job is complete
      my $ready=$self->_check_sub_status($j);

    }
  }
  else {
    # this job is not complete, no need to inform upstream
  }
}

method _inform_parent {
  my $job=shift;
  return unless $job and $job->[JOB_PARENT];

  #if($job->[JOB_STATE]

}
method cancel_jobs {
  my $id=shift;
  my $job=$_jobs->{$id};

  return undef unless defined $job;

  for($job->[JOB_STATE]){
    if($_ == JOB_STATE_SCHEDUALED){
      # In the schedualed list. Find by start time   and remove
      my $i=time_numeric_right $job->[JOB_START], $_schedualed;
      
      # $i is right most index of duplicates.. so continue search leftwards /down
      while($i > -1){
        if($_schedualed->[$i][JOB_ID]==$job->[JOB_ID]){
          splice @$_schedualed, $i, 1; 
          last;
        }
        $i--;
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
      #TODO: remove job after timer value
      delete $_jobs->{$id};
    }
    elsif($_ == JOB_STATE_ACTIVE){
      #sub_process_cancel
      my $p=$job->[JOB_PROCESS];
      if(ref $p){
        # A worker
        $p->close;
      }
      else {
        # Not a worker,
        sub_process_cancel $p;
      }
      $job->[JOB_STATE]=JOB_STATE_FAILED;
      #push @$_failed, $job;
    }
  }

}


# Remove the job and any informed jobs.
# Only removes complete or failed jobs at the top level
method remove_job {
  my $id=shift;
  my $job=$_jobs->{$id};
  last unless defined $job;

  # We only allow removal of 'ended' jobs at the top level
  last unless $job->[JOB_STATE]==JOB_STATE_COMPLETE;
  last unless $job->[JOB_STATE]==JOB_STATE_FAILED;

  # All informed jobs are not in the scheduled list due to the complete/failed
  # requirement
  my @removed;
  my @stack;
  push @stack,$id;
  while(@stack){
    my $id=pop @stack;
    push @removed, $id;
    my $job=$_jobs->{$id};

    $job=delete $_jobs->{$id};
    push @stack, $job->[JOB_INFORM]->@*;
  }

  @removed;
}


method status_job {
  my $id=shift;
  my $job=$_jobs->{$id};

  if($job){
    return $job->[JOB_STATE];
  }
}

# API linker system
# Create a job and set it up for linker callbacks
method io_job {

  #my ($work, $cb, $error)=@_;

  my $job=$self->create_job(@_);
  my $ex_cb=$job->[JOB_ON_COMPLETE];

  sub {
    my ($next, $index, @options)=@_;
    sub {
      # Set the callback of the job to call the ne
      $job->[JOB_ON_COMPLETE]=sub {

        # Do external callback for reporting?
        $ex_cb and &$ex_cb;
        
        # Auto link to next  job
        &$next;
      };

      # Calling this link scheduals and effectively starts the job
      $self->schedual_jobs($job);
    }
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

# load a class and ensure the rpc
method load_job {
 

}

# Helper for reports





1;

=head1 NAME

uSAC::Scheduler - Jobs on a schedule

=head1 DESCRIPTION


=head2 HOW IT WORKS

Jobs are added to a internal DB
Jobs are also added to a schedualed list if deps are met
When the job start time has started


Jobs are added to a 'schedualed' list, which is storted by start time (unix
time). When the current time is larger or equal to the start time, the job is
shifted into the 'immediate' queue, which is sorted by priority. As existing
jobs finish, the new jobs are poped of the immedate list.

If an high priority job needed asap exectution, it would be scheduled with the
current time (or less) as the start time, and the large value for the priority.
This would force it to the front of the queue and then processed at the next
available chance.

This is an in memory shedular only. To make a persisat, a front end can be
added.

