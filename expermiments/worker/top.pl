#!/usr/bin/env usac --backend AnyEvent
#
use uSAC::Worker;

my $worker;

use Data::Dumper;
my $broker=$uSAC::Main::Default_Broker;;


my $w=uSAC::Worker::create_worker;
asay $STDERR, "CREATED WORKER $w";
#########################################
# sub { timer 0, 1, sub {               #
#     #print STDERR "FROM WORKER $$\n"; #
#     asay $STDERR, "FROM WORKER $$\n"  #
#   }};                                 #
#########################################
#my $w2=uSAC::Worker::create_worker;

#my $timer=timer 0, 1, sub {asay $STDERR, "FROM PARENT $$"};

timer 2, 0, sub {
$broker->listen(undef,"^worker/(\\d+)/eval-return/(\\d+)\$", sub {

    asay $STDERR, "====REsults from eval ". Dumper @_;
  });
};

my $i=0;
my $t2=timer 3,1, sub {
  asay $STDERR, "$$ SENDING FOR EVAL";
    $broker->broadcast(undef,"worker/$w/eval/$i", "10*10");
    $i++;
};

############################################################
# $broker->listen(undef, ".*", sub {                       #
#     #asay $STDERR, "parent $$ GOT CATCH ALL ".Dumper @_; #
#                                                          #
#   });                                                    #
############################################################

1;
