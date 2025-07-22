#!/usr/bin/env usac --backend AnyEvent
#
use uSAC::Worker;


use Data::Dumper;
my $broker=$uSAC::Main::Default_Broker;;

my @workers;

######################################################
# $broker->listen(undef, ".*", sub {                 #
#     asay $STDERR, "C ATCH ALL PARENT ". Dumper @_; #
#   });                                              #
######################################################

push @workers, uSAC::Worker->new(), uSAC::Worker->new();

######################################################
# for my $w (@workers){                              #
#   $w->rpa("test", 'sub { return uc shift }', sub { #
#       asay $STDERR, "RPA RESULT", Dumper @_;       #
#       $w->rpc("test","payload", sub {              #
#           asay $STDERR, "RPC RESULT", Dumper @_;   #
#         });                                        #
#     });                                            #
#                                                    #
# }                                                  #
#                                                    #
######################################################
my $i=0;
my $t2; $t2=timer 0, 1, sub {
  for(@workers){
    if($i>=10){
      $_->close;
    }
    else {
      $_->eval(" for(1..1000000){sin 10*10};time", sub {
          asay $STDERR, "GOT RESULT", Dumper @_;
      });
      ##################################################
      # $_->rpc("test", 'lower case input data', sub { #
      #     asay $STDERR, "RESULT FROM RCP: $_[0]";    #
      #   });                                          #
      ##################################################
    }
    
  }
  $i++;
};

############################################################
# $broker->listen(undef, ".*", sub {                       #
#     #asay $STDERR, "parent $$ GOT CATCH ALL ".Dumper @_; #
#                                                          #
#   });                                                    #
############################################################
asay $STDERR, "END OR PROGRAM____";
1;
