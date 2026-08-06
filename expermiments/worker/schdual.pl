use uSAC::IO;
use uSAC::Scheduler;

use UUID qw<uuid4>;


my $sh=uSAC::Scheduler->new;


asay $STDERR, uuid4;

my $start=time+3;
asay $STDERR, "STARTING AT ===== $start";
my $job=uSAC::Scheduler::create_job(name=>"My job", start=> $start, interval=>1, expiry=> time +20, work=>'ls -al',
  on_complete=>sub {
    # expect the pid and status code?
    adump $STDERR, "ls JOB COMPLETE, @_";
  },

  on_result=>sub {
    # expect the final result for stdout?
    #adump $STDERR, "JOB RESULT :", @_;
  },
  on_complete=>sub {
    asay $STDERR, "JOB COMPLETE: ", @_;
  },

  on_start=>sub {
    adump $STDERR, "JOB start :", @_;
  }
);

my ($j) = $sh->schedual_jobs($job);

adump $STDERR, "JOB is ", $job, "with id: $j";

my $job2=uSAC::Scheduler::create_job(name=>"My job2", start=> 0, expiry=> time +20, work=>sub {
    my $w=shift;
    print STDERR "______DID SOME AMAZING WORK with $w ______\n"; 
    my $i=0;
    timer 0, 1, sub {
      $w->report("LOTS OF STUFF $i ");
      exit if $i++ >5;
    };
  },
  on_result=>sub {
    asay $STDERR, "JOB RESULT :", @_;
  },
  on_complete=>sub {
    asay $STDERR, "JOB COMPLETE: ", @_;
  },
  on_status=>sub{
    asay $STDERR, "JOB STATUS: ", @_;
  },
  on_start=>sub {
    asay $STDERR, "JOB start :", @_;
  },
  deps=>[$j]
);

my ($j2) = $sh->schedual_jobs($job2);
adump $STDERR, "JOB2 is ", $job2, "with id: $j2";

$sh->start;
