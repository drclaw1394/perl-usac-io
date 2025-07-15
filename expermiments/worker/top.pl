#!/usr/bin/env usac --backend AnyEvent
#
use uSAC::Worker;


use Data::Dumper;
my $broker=$uSAC::Main::Default_Broker;;

my @workers;


push @workers, uSAC::Worker::create_worker, uSAC::Worker::create_worker;


#timer 2, 0, sub {
    $broker->listen(undef,"^worker/(\\d+)/eval-return/(\\d+)\$", sub {

    asay $STDERR, "====REsults from eval ". Dumper @_;
  });
#};


my $i=0;
my $t2=timer 0, 0.1, sub {
  for(@workers){
    asay $STDERR, "$$ SENDING FOR EVAL $_";
    $broker->broadcast(undef,"worker/$_/eval/$i", "for(1..1000000){sin 10*10}; 1");
    $i++;
  }
};

############################################################
# $broker->listen(undef, ".*", sub {                       #
#     #asay $STDERR, "parent $$ GOT CATCH ALL ".Dumper @_; #
#                                                          #
#   });                                                    #
############################################################
asay $STDERR, "END OR PROGRAM____";
1;
