package uSAC::Worker;
use Data::FastPack;
use uSAC::FastPack::Broker;
use uSAC::IO;
use uSAC::Log;
use Log::OK;
use Data::Dumper;
use constant::more DEBUG=>0;
use Socket::More::Lookup qw'getaddrinfo';
use Object::Pad;

use feature "try";
no warnings "experimental";

# The perl code which can be called by name


class uSAC::Worker;

field $_rpc         :param = undef;
field $_on_complete :param = undef;
field $_work        :param = undef;
field $_wid         :reader;
field $_io;
field $_broker      :param = undef;
field $_bridge;
field $_seq;
field $_active;


BUILD {
  asay $STDERR , "--CALLING CREATE WORKER----";
  $_seq=0;
  $_active={};
  $_broker//=$uSAC::Main::Default_Broker;

  $_rpc->{eval}=sub {

  };
  my $__on_complete=sub {
    # unregister worker?
    $self->_clean_up;

    $_on_complete and &$_on_complete
  };

  my $__work//=sub {
    $_wid=$$; # NOTE: needed for child to know its worker id

    asay  $STDERR, "++++++DOING CHILD SETUP for wid $_wid+++";
    $self->_child_setup;
    $_work and &$_work;
  };

  @$_io=sub_process $__work, $__on_complete;
  $_wid=$_io->[3]; #NOte this is only in parent
  asay $STDERR, "======asdfasdfasdfasdfasdfasdf $_wid";
  if(@$_io){
    #Do parent stuff here
    $self->_parent_setup;
    $_io->[2]->pipe_to($STDERR);

  }
  else {
    # Error in parent

  }
}

method eval {
  my $string=shift;
  my $cb=shift;

  #asay $STDERR, "$$ SENDING FOR EVAL to $_wid";
  $_active->{++$_seq}=$cb;
  $_broker->broadcast(undef,"worker/$_wid/eval/$_seq", $string);
}

method rpa {
  my $name=shift;
  my $string=shift;
  my $cb=shift;
  $_active->{++$_seq}=$cb;
  $_broker->broadcast(undef,"worker/$_wid/rpa/$name/$_seq", $string);
}

method rpc {
  my $name=shift;
  my $string=shift;
  my $cb=shift;
  $_active->{++$_seq}=$cb;
  $_broker->broadcast(undef,"worker/$_wid/rpc/$name/$_seq", $string);
}



method close {
  $_bridge->close;
  sub_process_cancel $_wid;
  @$_io=undef;
  #$_wid=undef;
}

method _clean_up {
  asay $STDERR, "---- CLEAN UP WORKER----";
  my $forward_sub=$_bridge->forward_message_sub;

  $_broker->ignore($_bridge->source_id, "^worker/$_wid/", $forward_sub);
}

# Setup child bridge to parent
method _child_setup {
  #Log::OK::TRACE and log_trace "Configuring worker (rpc) interface in child"; 
  # TODO: remove all worker registrations in broker as we are not interested in  existing working registrations
  #

  $_bridge=uSAC::FastPack::Broker::Bridge->new(broker=>$_broker, reader=>$STDIN, writer=>$STDOUT, rfd=>0,  wfd=>1);
  $_broker->add_bridge($_bridge);
  $_broker->listen($_bridge->source_id,"^worker/$_wid/", $_bridge->forward_message_sub);


  # Now register for messages from parent
  $_broker->listen(undef, "^worker/$_wid/rpa/(\\w+)/(\\d+)", sub {
      asay $STDERR, "========== IN RPA==============";
      # Add a procedure which we can call
      #
      my $sender=shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name= $cap->[0];
        my $seq= $cap->[1];

        local $@;
        my $sub=eval $msg->[FP_MSG_PAYLOAD];
        if($@){
          # Error.   
          my $error=Error::Show::context error=>$@;
          $_broker->broadcast(undef,"worker/$_wid/rpa-error/$name/$seq", $error);
        }
        else {
          $_rpc->{$name}=$sub;
          $_broker->broadcast(undef,"worker/$_wid/rpa-return/$name/$seq", 1);
          asay $STDERR, "INSTALLED REMOTE PROCEEDURES for name $name seq $seq: ".Dumper $_rpc;
        }
      }

    });

  $_broker->listen(undef, "^worker/$_wid/rpc/(\\w+)/(\\d+)", sub {
      # call a procedure
      my $sender=shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name= $cap->[0];
        my $seq= $cap->[1];
        my $sub= $_rpc->{$name};

        if($sub){
          try {
            $_broker->broadcast(undef, "worker/$_wid/rpc-return/$name/$seq", $sub->($msg->[FP_MSG_PAYLOAD]));
          }
          catch($e){
            my $error=Error::Show::context error=>$e;
            $_broker->broadcast(undef,"worker/$_wid/rpc-error/$name/$seq", $error);
          }
        }
        else {
          $_broker->broadcast(undef,"worker/$_wid/rpc-error/$name/$seq", "RPC NOT FOUND");
        }
      }
    });

  $_broker->listen(undef, "^worker/$_wid/eval/(\\d+)", sub {

      #DEBUG and asay $STDERR, " IN CLIENT EVAL LISTENER============== ". Dumper @_;
      # call a procedure
      my $sender=shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        #asay $STDERR, " IN CLIENT EVAL LISTENER msg ============== ". Dumper $msg;
        my $seq= $cap->[0];

          local $@;
          my $res=eval $msg->[FP_MSG_PAYLOAD];
          #asay $STDERR, "WORKER Result of EVAL REQUEST Is $res  for seq $seq=====";
          unless($@){
            $_broker->broadcast(undef, "worker/$_wid/eval-return/$seq", $res);
          }
          else{

            my $error=Error::Show::context error=>$@;
            asay $STDERR,  $error;
            $_broker->broadcast(undef,"worker/$_wid/eval-error/$seq", $error);
          }
      }
    });

  my $sub;
  $sub= sub {
    use feature 'state';
    state $i=0;
    DEBUG and asay $STDERR, "TIMER IN CHILD WORKER-----";
    $_broker->broadcast(undef, "worker/$_wid/status/$i", "Hello from $_wid");
    $i++;
    timer 1,0, $sub;

  };
  timer 1, 0, $sub;

  asay $STDERR, "--SETUP UP CHILDE TIMER=---";
  my $t = timer 0, 1, sub {
    asay $STDERR, "--CHILD TIMER--";
  };
}

# Setup parent bridge to child
method _parent_setup {
  asay $STDERR, "PARENT SETUP "."@$_io";
  $_bridge=uSAC::FastPack::Broker::Bridge->new(broker=>$_broker, reader=>$_io->[1], writer=>$_io->[0], rfd=>$_io->[1]->fh,  wfd=>$_io->[0]->fh);

  my $forward_sub=$_bridge->forward_message_sub;
  $_broker->add_bridge($_bridge);

  # Listen for any local messages and forward to other end of bridge
  #
  $_broker->listen($_bridge->source_id, "^worker/$_wid/", $forward_sub);
  
  # Add Eval support
  $_broker->listen(undef, "^worker/$_wid/eval-return/(\\d+)\$", sub {
      #asay $STDERR, "====REsults from eval ". Dumper @_;
    shift $_[0]->@*;
    for my ($msg, $cap)($_[0][0]->@*){
      my $i=$cap->[0];   
      my $cb=delete $_active->{$i};
      $cb and $cb->($msg->[FP_MSG_PAYLOAD]);
    }

  });

  $_broker->listen(undef,"^worker/$_wid/eval-error/(\\d+)\$", sub {
    shift $_[0]->@*;
    asay $STDERR, "====REsults from eval ". Dumper @_;
    for my ($msg, $cap)($_[0][0]->@*){
      my $i=$cap->[0];   
      my $cb=delete $_active->{$i};
      $cb and $cb->($msg->[FP_MSG_PAYLOAD]);
    }

  });



  # Add RPA support
  $_broker->listen(undef, "^worker/$_wid/rpa-return/(\\w+)/(\\d+)\$", sub {
    shift $_[0]->@*;
    for my ($msg, $cap)($_[0][0]->@*){
      my $name=$cap->[0];
      my $i=$cap->[1];   
      asay $STDERR, "RPA RETURN----- $_wid  $name";
      my $cb=delete $_active->{$i};
      $cb and $cb->($msg->[FP_MSG_PAYLOAD]);
    }
  });

  $_broker->listen(undef, "^worker/$_wid/rpa-error/(\\w+)/(\\d+)\$", sub {
    shift $_[0]->@*;
    for my ($msg, $cap)($_[0][0]->@*){
      my $i=$cap->[1];   
      my $name=$cap->[0];
      asay $STDERR, "RPA ERROR----- $_wid  $name";
      my $cb=delete $_active->{$i};
      $cb and $cb->($msg->[FP_MSG_PAYLOAD]);
    }

  });

  # Add RPC support
  $_broker->listen(undef, "^worker/$_wid/rpc-return/(\\w+)/(\\d+)\$", sub {
    shift $_[0]->@*;
    for my ($msg, $cap)($_[0][0]->@*){
      my $name=$cap->[0];
      my $i=$cap->[1];   
      asay $STDERR, "RPC RETURN----- $_wid  $name";
      my $cb=delete $_active->{$i};
      $cb and $cb->($msg->[FP_MSG_PAYLOAD]);
    }
  });

  $_broker->listen(undef, "^worker/$_wid/rpc-error/(\\w+)/(\\d+)\$", sub {
    shift $_[0]->@*;
    for my ($msg, $cap)($_[0][0]->@*){
      my $i=$cap->[1];   
      my $name=$cap->[0];
      asay $STDERR, "RPC ERROR----- $_wid  $name";
      my $cb=delete $_active->{$i};
      $cb and $cb->($msg->[FP_MSG_PAYLOAD]);
    }

  });




  $_io->[2]->pipe_to($STDERR);


  

  # Now register for messages from worker
  #
  $_broker->listen(undef, "^worker/$_wid/status/(\\d+)\$", sub {
  #$broker->listen(undef, ".*", sub {
      # Trigger the reporting of worker status
      #
      #asay $STDERR, "STAUTS FROM WORKER is: ".Dumper @_;

    });
  
  asay $STDERR, "--SETUP UP PARENT TIMER=---";
  my $t = timer 0, 1, sub {
    asay $STDERR, "--PARENT TIMER--";
  };
}




1;
