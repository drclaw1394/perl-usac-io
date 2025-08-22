package uSAC::Worker;
use Data::FastPack;
use uSAC::FastPack::Broker;
use uSAC::IO;
use uSAC::Log;
use Log::OK;
use Data::Dumper;
use constant::more DEBUG=>0;
use Object::Pad;

use feature "try";
no warnings "experimental";

# The perl code which can be called by name


class uSAC::Worker;
use feature "try";
no warnings "experimental";

field $_rpc         :param = undef;
field $_on_complete :param = undef;
field $_work        :param = undef;
field $_args        :param = undef;
field $_wid         :reader;          #The backend process id
field $_io;
field $_broker      :param = undef;
field $_bridge;
field $_seq;
field $_active;
field $_register;

field $_call_max   :param = 5000;     # Max calls of a single process. a new process is created after this count
field $_call_count;

field $_queue;

BUILD {
  #DEBUG and 
  #asay $STDERR , "--CALLING CREATE WORKER----";
  $_seq=0;
  $_call_count=0;
  $_active={};
  $_register=[];
  $_broker//=$uSAC::Main::Default_Broker;
  $_queue=[];
  # install Eval rpc call

  $_rpc->{eval}=sub {
      eval shift;
  };

  DEBUG and asay $STDERR, Dumper $_rpc;
  $self->_sub_process if defined $_work;

}

# Create the actual process
method _sub_process {
  DEBUG and asay $STDERR, "---CALLED _subprocess in worker";
  my $__on_complete=sub {
    # unregister worker?
    $_on_complete and &$_on_complete
  };

  my $__work//=sub {
    $_wid=$$; # NOTE: needed for child to know its worker id

    DEBUG and asay  $STDERR, "++++++DOING CHILD SETUP for wid $_wid+++";
    $self->_child_setup;
    $_work and &$_work;
  };

  DEBUG and asay $STDERR, "---Just before sub_process IO call";
  @$_io=sub_process $__work, $__on_complete;
  $_wid=$_io->[3]; #NOte this is only in parent
  DEBUG and asay $STDERR, "____CALLING SUB_PROCESS IN WORKER .. new id $_wid";
  DEBUG and asay $STDERR, "======asdfasdfasdfasdfasdfasdf $_wid";
  if(@$_io){
    #Do parent stuff here
    $self->_parent_setup;
    $_io->[2]->pipe_to($STDERR);

  }
  else {
    # Error in parent
    DEBUG and asay $STDERR, "---- ERROR IN PARENT";
  }
}

method eval {
  my $string=shift;
  my $cb=shift;
  my $error=shift;

  #asay $STDERR, "$$ SENDING FOR EVAL to $_wid";
  $_active->{++$_seq}=[$cb, $error];
  $_broker->broadcast(undef,"worker/$_wid/rpc/eval/$_seq", $string);
  $_seq;
}

method rpa {
  my $name=shift;
  my $string=shift;
  my $cb=shift;
  my $error=shift;
  $_active->{++$_seq}=[$cb, $error];
  $_broker->broadcast(undef,"worker/$_wid/rpa/$name/$_seq", $string);
  $_seq;
}

method rpc {
  my $name=shift; # Name could be code ref
  my $string=shift;
  my $cb=shift;
  my $error=shift;
  push @$_queue, [$name, $string, $cb, $error];
  unless(keys %$_active){
    # Kick start
    $self->do_rpc;
  }
}

method do_rpc {
  return unless @$_queue;
  my $e=shift @$_queue;
  DEBUG and asay $STDERR, "---WORKER RPC CALLED";
  my $name=shift @$e; # Name could be code ref
  my $string=shift @$e;
  my $cb=shift @$e;
  my $error=shift @$e;

  if($_rpc->{$name}){
    DEBUG and asay $STDERR, "WORKER id before  sub process $_wid";
    $self->_sub_process unless $_wid;
    $_call_count++;
    $_active->{++$_seq}=[$cb, $error];
    $_broker->broadcast(undef,"worker/$_wid/rpc/$name/$_seq", $string);
    return $_seq;
  }
  else {
    DEBUG and asay $STDERR, "--RPC name not it worker $name";
  }
  undef;
}



method close {
  #asay $STDERR, "---CLOSING WORKER---";
  return unless $_wid;
  $_bridge->close;

  sub_process_cancel $_wid;
  @$_io=();#undef;
  $_wid=undef;
  $self->_clean_up;

}

method _clean_up {
  DEBUG and asay $STDERR, "---- CLEAN UP WORKER----";
  #my $forward_sub=$_bridge->forward_message_sub;

  DEBUG and asay $STDERR, Dumper $_register;
  #$_broker->ignore($_bridge->source_id, "^worker/$_wid/", $forward_sub);
  for(@$_register){
    DEBUG and asay $STDERR, " to ignore in cleanup ".Dumper $_;
    $_broker->ignore(@$_);
  }
  $_register=[];
  $_call_count=0;
  $_broker->remove_bridge($_bridge) if $_bridge;
  DEBUG and asay $STDERR, "---- END OF CLEAN UP WORKER----";
}

# Setup child bridge to parent
method _child_setup {
  #asay $STDERR, "-- IN CHILD SETUP";
  # remove existing registrations
  $self->_clean_up;
  DEBUG and Log::OK::TRACE and log_trace "Configuring worker (rpc) interface in child"; 
  # TODO: remove all worker registrations in broker as we are not interested in  existing working registrations
  #

  $STDIN->pause;
  $_bridge=uSAC::FastPack::Broker::Bridge->new(broker=>$_broker, reader=>$STDIN, writer=>$STDOUT, rfd=>0,  wfd=>1);
  $_broker->add_bridge($_bridge);
  $_broker->listen($_bridge->source_id,"^worker/$_wid/", $_bridge->forward_message_sub);
  #$_broker->listen(undef ,"^worker/$_wid/", $_bridge->forward_message_sub);


  # Now register for messages from parent
  $_broker->listen(undef, "^worker/$_wid/rpa/(\\w+)/(\\d+)", sub {
      DEBUG and asay $STDERR, "========== IN RPA==============";
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
          DEBUG and asay $STDERR, "INSTALLED REMOTE PROCEEDURES for name $name seq $seq: ".Dumper $_rpc;
        }
      }

    });

  $_broker->listen(undef, "^worker/$_wid/rpc/(\\w+)/(\\d+)", sub {
      # call a procedure
      DEBUG and asay $STDERR, "child rpc called";
      my $sender=shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name= $cap->[0];
        my $seq= $cap->[1];
        my $sub= $_rpc->{$name};

        if($sub){
          try {
            my $res=$sub->($msg->[FP_MSG_PAYLOAD]);
            DEBUG and asay $STDERR, "child rpc result ". Dumper $res;
            $_broker->broadcast(undef, "worker/$_wid/rpc-return/$name/$seq", $res);
            $_broker->broadcast(undef, "worker/$_wid/rpc-return/$name/$seq", undef);
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
      $_broker->clear_cache;
    });


  my $sub;
  $sub= sub {
    use feature 'state';
    state $i=0;
    #DEBUG and asay $STDERR, "TIMER IN CHILD WORKER-----";
    $_broker->broadcast(undef, "worker/$_wid/status/$i", "Hello from $_wid");
    $i++;
    timer 1,0, $sub;

  };
  timer 1, 0, $sub;

  DEBUG and Log::OK::TRACE and log_trace "END Configuring worker (rpc) interface in child"; 

  $uSAC::Main::WORKER=$self;
  

  ################################################
  # asay $STDERR, "--SETUP UP CHILDE TIMER=---"; #
  # my $t = timer 0, 1, sub {                    #
  #   asay $STDERR, "--CHILD TIMER--";           #
  # };                                           #
  ################################################
}

# Setup parent bridge to child
method _parent_setup {
  DEBUG and asay $STDERR, "PARENT SETUP "."@$_io";
  $_bridge=uSAC::FastPack::Broker::Bridge->new(broker=>$_broker, reader=>$_io->[1], writer=>$_io->[0], rfd=>$_io->[1]->fh,  wfd=>$_io->[0]->fh);

  my $forward_sub=$_bridge->forward_message_sub;
  $_broker->add_bridge($_bridge);

  my $r;
  # Listen for any local messages and forward to other end of bridge
  #
  $r=[$_bridge->source_id, "^worker/$_wid/", $forward_sub];
  $_broker->listen(@$r);
  push @$_register, $r;
  #$_broker->listen(undef, "^worker/$_wid/", $forward_sub);
  
  $r=[undef, "^worker/$_wid/rpa-return/(\\w+)/(\\d+)\$", sub {
      shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name=$cap->[0];
        my $i=$cap->[1];   
        DEBUG and asay $STDERR, "RPA RETURN----- $_wid  $name";
        my $e=delete $_active->{$i};
        $e->[0] and $e->[0]->($msg->[FP_MSG_PAYLOAD]);
      }
    }];
  # Add RPA support
  $_broker->listen(@$r);
  push @$_register, $r;

  $r=[
    undef, "^worker/$_wid/rpa-error/(\\w+)/(\\d+)\$", sub {
      shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $i=$cap->[1];   
        my $name=$cap->[0];
        DEBUG and asay $STDERR, "RPA ERROR----- $_wid  $name";
        my $e=delete $_active->{$i};
        $e->[0] and $e->[0]->($msg->[FP_MSG_PAYLOAD]);
      }

    }
  ];
  $_broker->listen(@$r);
  push @$_register, $r;
  $r=[
    undef, "^worker/$_wid/rpc-return/(\\w+)/(\\d+)\$", sub {
      #DEBUG and 
      #asay $STDERR, "$$ RPC RETURN in server----- ". Dumper @_;
      shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name=$cap->[0];
        my $i=$cap->[1];   
        DEBUG and asay $STDERR, "RPC RETURN----- $_wid  $name";
        my $e=delete $_active->{$i};

        $_broker->broadcast(undef,"worker/$_wid/rpc/$name/$i", undef);
        if($_call_count >= $_call_max){
          DEBUG and asay $STDERR, "=======MAX CALL COUNT REACHED";
          $self->_clean_up;
          $self->close;
        }

        DEBUG and asay $STDERR, "======= about to do callback";
        $e->[0] and $e->[0]->($msg->[FP_MSG_PAYLOAD]);
        $_broker->clear_cache;
        $self->do_rpc;
      }
    }
  ];

  # Add RPC support
  $_broker->listen(@$r);
  push @$_register,$r;

  $r=[
    undef, "^worker/$_wid/rpc-error/(\\w+)/(\\d+)\$", sub {
      shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $i=$cap->[1];   
        my $name=$cap->[0];
        DEBUG and asay $STDERR, "RPC ERROR----- $_wid  $name $msg->[FP_MSG_PAYLOAD]";
        my $e=delete $_active->{$i};
        $e->[1] and $e->[1]->($msg->[FP_MSG_PAYLOAD]);
      }
    }
  ];

  $_broker->listen(@$r);
  push @$_register, $r;


  $_io->[2]->pipe_to($STDERR);


  

  # Now register for messages from worker
  #
  $r=[
    undef, "^worker/$_wid/status/(\\d+)\$", sub {
  #$broker->listen(undef, ".*", sub {
      # Trigger the reporting of worker status
      #
      #asay $STDERR, "STATUS FROM WORKER is: ".Dumper @_;

    }
  ];

  $_broker->listen(@$r);
  push @$_register, $r;
  

  #asay $STDERR, "END OF PARENT SETUP: ".Dumper $_register;
  ################################################
  # asay $STDERR, "--SETUP UP PARENT TIMER=---"; #
  # my $t = timer 0, 1, sub {                    #
  #   asay $STDERR, "--PARENT TIMER--";          #
  # };                                           #
  ################################################
}




1;
