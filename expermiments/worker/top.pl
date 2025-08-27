#!/usr/bin/env usac --backend AnyEvent
#
use uSAC::Worker;


use Data::Dumper;
my $broker=$uSAC::Main::Default_Broker;;

my @workers;


push @workers, uSAC::Worker->new(), uSAC::Worker->new();

my $i=0;
my $t2; $t2=timer 0, 1, sub {
  for(@workers){
    if($i>=10){
      $_->close;
      timer_cancel $t2;
    }
    else {
      $_->eval(" for(1..10000000){sin 10*10};time", sub {
          asay $STDERR, "GOT RESULT", Dumper @_;
      },
      sub {
        asay $STDERR, "GOT AND ERROR", Dumper @_;
      }
    );
      ##################################################
      # $_->rpc("test", 'lower case input data', sub { #
      #     asay $STDERR, "RESULT FROM RCP: $_[0]";    #
      #   });                                          #
      ##################################################
    }
    
  }
  $i++;
};

asay $STDERR, "END OR PROGRAM____";
1;
