package uSAC::Worker;
use Data::FastPack;
use uSAC::FastPack::Broker;
use uSAC::IO;
use uSAC::Log;
use Log::OK;
use Data::Dumper;
use constant::more DEBUG=>0;

use feature "try";
no warnings "experimental";

# The perl code which can be called by name

my %remote_procedures;


# Setup child bridge to parent
sub _child_setup {
  my $wid=shift;
  #Log::OK::TRACE and log_trace "Configuring worker (rpc) interface in child"; 
  # TODO: remove all worker registrations in broker as we are not interested in  existing working registrations
  #
  my $broker=$uSAC::Main::Default_Broker;

  my $bridge=uSAC::FastPack::Broker::Bridge->new(broker=>$broker, reader=>$STDIN, writer=>$STDOUT, rfd=>0,  wfd=>1);
  $broker->add_bridge($bridge);
  $broker->listen($bridge->source_id,"^worker/$wid/", $bridge->forward_message_sub);


  # Now register for messages from parent
  $broker->listen(undef, "^worker/$wid/rpa/(\\w+)/(\\d+)", sub {

      # Add a procedure which we can call
      #
      my $sender=shift;
      for my ($msg, $cap)($_[0]->@*){
        my $name= $cap->[0];
        my $seq= $cap->[1];

        local $@;
        my $sub=eval $msg->[FP_MSG_PAYLOAD];
        if($@){
          # Error.   
          my $error=Error::Show::context error=>$@;
          $broker->broadcast(undef,"worker/$wid/rpa-error/$name/$seq", $error);
        }
        else {
          $broker->broadcast(undef,"worker/$wid/rpa-success/$name/$seq", 1);
          $remote_procedures{$name}=$sub;
          DEBUG and asay $STDERR, 'INSTALLED REMOTE PROCEEDURES: '.Dumper $remote_procedures;
        }
      }

    });

  $broker->listen(undef, "^worker/$wid/rpc/(\\w+)/(\\d+)", sub {
      # call a procedure
      my $sender=shift;
      for my ($msg, $cap)($_[0]->@*){
        my $name= $cap->[0];
        my $seq= $cap->[1];
        my $sub= $remote_procedures{$name}=$sub;

        if($sub){
          try {
            $broker->broadcast(undef, "worker/$wid/rpc-return/$name/$seq", $sub->($msg->[FP_MSG_PAYLOAD]));
          }
          catch($e){
            my $error=Error::Show::context error=>$e;
            $broker->broadcast(undef,"worker/$wid/rpc-error/$name/$seq", $error);
          }
        }
        else {
          $broker->broadcast(undef,"worker/$wid/rpc-unknown/$name/$seq", 1);
        }
      }
    });

  $broker->listen(undef, "^worker/$wid/eval/(\\d+)", sub {

      #DEBUG and asay $STDERR, " IN CLIENT EVAL LISTENER============== ". Dumper @_;
      # call a procedure
      my $sender=shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        #asay $STDERR, " IN CLIENT EVAL LISTENER msg ============== ". Dumper $msg;
        my $seq= $cap->[0];

        my $res=eval $msg->[FP_MSG_PAYLOAD];
        #asay $STDERR, "Result of EVAL REQUEST Is $res  for seq $seq=====";
        try {
          $broker->broadcast(undef, "worker/$wid/eval-return/$seq", $res);
        }
        catch($e){
          my $error=Error::Show::context error=>$e;
          $broker->broadcast(undef,"worker/$wid/eval-error/$seq", $error);
        }
      }
    });

  my $sub;
  $sub= sub {
    use feature 'state';
    state $i=0;
    DEBUG and asay $STDERR, "TIMER IN CHILD WORKER-----";
    $broker->broadcast(undef, "worker/$wid/status/$i", "Hello from $wid");
    $i++;
    timer 1,0, $sub;

  };
  timer 1, 0, $sub;

  asay $STDERR, "--SETUP UP CHILDE TIMER=---";
  my $t = timer 0, 1, sub {
    asay $STDERR, "--CHILD TIMER--";
  };
  #############################################
  # $broker->listen(undef, ".*", sub {        #
  #     asay $STDERR, "WOKER side CATCH ALL"; #
  #     asay $STDERR, Dumper  @_;             #
  #     #$broker->                            #
  # });                                       #
  #############################################
}

# Setup parent bridge to child
sub _parent_setup {
  my $io=shift;
  my $wid=$io->[3];
  DEBUG and asay $STDERR, "PARENT SETUP "."@$io";
  my $broker=$uSAC::Main::Default_Broker;
  my $bridge=uSAC::FastPack::Broker::Bridge->new(broker=>$broker, reader=>$io->[1], writer=>$io->[0], rfd=>$io->[1]->fh,  wfd=>$io->[0]->fh);

  my $forward_sub=$bridge->forward_message_sub;
  $broker->add_bridge($bridge);
  $broker->listen($bridge->source_id,"^worker/$wid/", $forward_sub);

  $io->[2]->pipe_to($STDERR);


  

  # Now register for messages from worker
  #
  $broker->listen(undef, "^worker/$wid/status/(\\d+)\$", sub {
  #$broker->listen(undef, ".*", sub {
      # Trigger the reporting of worker status
      #
      asay $STDERR, "STAUTS FROM WORKER is: ".Dumper @_;

    });
  ###############################################################
  # $broker->listen(undef, ".*", sub {                          #
  #     #asay $STDERR, "CATCH ALL in PARENTE SETUP", Dumper @_; #
  #   });                                                       #
  ###############################################################
  
  asay $STDERR, "--SETUP UP PARENT TIMER=---";
  my $t = timer 0, 1, sub {
    asay $STDERR, "--PARENT TIMER--";
  };
}


sub create_worker {
  asay $STDERR , "--CALLING CREATE WORKER----";
  my $work=shift;
  my $on_complete=shift;
  $work//=\&_child_setup;
  my @io=sub_process $work, $on_complete;
  my $id=$io[3];
####
#  #
####
  if(@io){
    #Do parent stuff here
    #timer 1, 0, sub {_parent_setup \@io;};
    _parent_setup \@io;
    $io[2]->pipe_to($STDERR);

  }
  else {
    # Error in parent

  }
  $id;
}


########################################################################################################################
# sub setup_template {                                                                                                 #
#                                                                                                                      #
#   Log::OK::TRACE and log_trace "Configuring worker (rpc) interface";                                                 #
#   my $broker=$uSAC::Main::Default_Broker;                                                                            #
#                                                                                                                      #
#   my $bridge=uSAC::FastPack::Broker::Bridge->new(broker=>$broker, reader=>$STDIN, writer=>$STDOUT, rfd=>0,  wfd=>1); #
#   $broker->add_bridge($bridge);                                                                                      #
#                                                                                                                      #
#                                                                                                                      #
#   # Register for control messages                                                                                    #
#   #                                                                                                                  #
#   $broker->listen(undef, "worker/spawn/(\d+)", sub {                                                                 #
#       shift @_;                                                                                                      #
#                                                                                                                      #
#       for my ($msg, $cap)($_[0]->@*){                                                                                #
#                                                                                                                      #
#         my $id=$msg->[FP_MSG_PAYLOAD];                                                                               #
#                                                                                                                      #
#         # NOTE: Currently only supports perl code                                                                    #
#         # Use subprocess directly to run arbitary code                                                               #
#         #                                                                                                            #
#                                                                                                                      #
#         # Fork this process as it is a template                                                                      #
#         sub_process undef,                                                                                           #
#                                                                                                                      #
#         sub {                                                                                                        #
#           # On complete. Called in parent                                                                            #
#                                                                                                                      #
#         },                                                                                                           #
#                                                                                                                      #
#         sub {                                                                                                        #
#           # on _fork                                                                                                 #
#           # Called in child                                                                                          #
#           # Restart the reader to ensure commands are processed                                                      #
#                                                                                                                      #
#           $STDIN->start;                                                                                             #
#                                                                                                                      #
#           $broker->listen(undef, "^worker/$id/rpa/(\w+)/(\d+)", sub {                                                #
#                                                                                                                      #
#               # Add a procedure which we can call                                                                    #
#               #                                                                                                      #
#               my $sender=shift;                                                                                      #
#               for my ($msg, $cap)($_[0]->@*){                                                                        #
#                 my $name= $cap->[0];                                                                                 #
#                 my $id= $cap->[1];                                                                                   #
#                                                                                                                      #
#                 local $@;                                                                                            #
#                 my $sub=eval $msg->[FP_MSG_PAYLOAD];                                                                 #
#                 if($@){                                                                                              #
#                   # Error.                                                                                           #
#                   my $error=Error::Show::context error=>$@;                                                          #
#                   $broker->broadcast(undef,"worker/$id/rpa-error/$name/$id", $error);                                #
#                 }                                                                                                    #
#                 else {                                                                                               #
#                   $broker->broadcast(undef,"worker/$id/rpa-success/$name/$id", 1);                                   #
#                   $remote_procedures{$name}=$sub;                                                                    #
#                 }                                                                                                    #
#               }                                                                                                      #
#                                                                                                                      #
#             });                                                                                                      #
#                                                                                                                      #
#           $broker->listen(undef, "^worker/$id/rpc/(\w+)/(\d+)", sub {                                                #
#               # call a procedure                                                                                     #
#               my $sender=shift;                                                                                      #
#               for my ($msg, $cap)($_[0]->@*){                                                                        #
#                 my $name= $cap->[0];                                                                                 #
#                 my $id= $cap->[1];                                                                                   #
#                 my $sub= $remote_procedures{$name}=$sub;                                                             #
#                                                                                                                      #
#                 if($sub){                                                                                            #
#                   try {                                                                                              #
#                     $sub->($msg->[FP_MSG_PAYLOAD]);                                                                  #
#                   }                                                                                                  #
#                   catch($e){                                                                                         #
#                     my $error=Error::Show::context error=>$e;                                                        #
#                     $broker->broadcast(undef,"worker/$id/rpc-error/$name/$id", $error);                              #
#                   }                                                                                                  #
#                 }                                                                                                    #
#                 else {                                                                                               #
#                   $broker->broadcast(undef,"worker/$id/rpc-unknown/$name/$id", 1);                                   #
#                 }                                                                                                    #
#               }                                                                                                      #
#             });                                                                                                      #
#         };                                                                                                           #
#                                                                                                                      #
#       }                                                                                                              #
#                                                                                                                      #
#     }                                                                                                                #
#   );                                                                                                                 #
#                                                                                                                      #
#                                                                                                                      #
#                                                                                                                      #
#                                                                                                                      #
#   $broker->listen(undef, "worker/kill/(\d+)", sub {                                                                  #
#       # Kill this worker, rea                                                                                        #
#       $bridge->close;                                                                                                #
#     });                                                                                                              #
#                                                                                                                      #
#   $broker->listen(undef, "^worker/reap/(d+)", sub {                                                                  #
#       # Reap                                                                                                         #
#       #                                                                                                              #
#                                                                                                                      #
#     });                                                                                                              #
#                                                                                                                      #
#   $broker->listen(undef, "^worker/status/(\d+)", sub {                                                               #
#       # Trigger the reporting of worker status                                                                       #
#       #                                                                                                              #
#                                                                                                                      #
#     });                                                                                                              #
#                                                                                                                      #
# }                                                                                                                    #
########################################################################################################################
1;
