use uSAC::IO;
use uSAC::Scheduler;



my $sh=uSAC::Scheduler->new;




my $job=$sh->create_job(name=>"My job", start=> time +3, interval=>2, expiry=> time +10, work=>'ls -al');

my $j = $sh->schedual_job($job);

my $job2=$sh->create_job(name=>"My job2", start=> 0, expiry=> time +10, work=>sub {
    my $w=shift;
    print STDERR "______DID SOME AMAZING WORK with $w ______\n"; 
    my $i=0;
    timer 0, 1,sub {
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
  deps=>[$j]
);

my $j2 = $sh->schedual_job($job2);
$sh->start;
