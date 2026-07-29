package uSAC::Worker;
use v5.36;
use Data::FastPack;
#use uSAC::FastPack::Broker;
use uSAC::FastPack::Broker::Bridge::Streaming;
use uSAC::IO;
use uSAC::Log;
use Log::OK;
use constant::more DEBUG=>0;
use Object::Pad;
#use Data::Dumper;
use Data::Dumper;

use feature "try";
no warnings "experimental";

# The perl code which can be called by name


class uSAC::Worker;
use feature "try";
no warnings "experimental";

field $_rpc         :param = undef;
field $_on_complete :param = undef;   # Callback expecting a single argument as [$status, pid]; 
field $_on_child    :param = undef;
field $_on_result   :param = undef;   # Callback for payload updates
field $_on_status   :param = undef;   # Callback for status updates
field $_work        :param = undef;   # Work to do (a sub ref or cmd string)
field $_args        :param = undef;   # Args to pass to the sub ref
field $_wid         :reader;          #The backend process id
field $_name        :param = undef;   #Name of process
field $_io;
field $_broker      :param = undef;
field $_bridge	    :reader;		
field $_seq;
field $_active;
field $_register;
field $_parent_pid;

field $_call_max   :param = 5000;     # Max calls of a single process. a new process is created after this count
field $_shrink      :param = undef;
field $_call_count;
field $_shrink_mask :mutator;
field $_queue;

BUILD {
  #DEBUG and 
  #asay $STDERR , "--CALLING CREATE WORKER----";
  $_seq=0;
  $_call_count=0;
  $_shrink//=1;
  $_shrink_mask=1;
  $_active={};
  $_register=[];
  $_broker//=$uSAC::Main::Default_Broker;
  $_queue=[];
  $_parent_pid=$$;
  # install Eval rpc call

  $_rpc->{eval}=sub {
      eval shift;
  };
  $_name//="uSAC::Worker";

  my $r;
  $r=[
	  undef,"post-fork", sub {
		  return if $$ == $_parent_pid;

		  #if($_parent_pid != $$){
      #say STDERR " =-=-=-POST FORK pid $$, parent PID $_parent_pid Worker id $_wid";
		#}

	  # Close all workers not in parent and that are not this process
	  if($$ != $_wid){
  		  push @$_register, $r;
		  $r=undef;
		  # NOTE asap call is important here
		  asap sub {$self->close};
		  #$self->close
	  }
	  else {
      ## say STDERR "-- KEEP WORKER pid $$ wid $_wid ";
	  }
  }];

  $_broker->listen(@$r);
  

  asay_now $STDERR, "-- in worker BUILD $_work";
  #DEBUG and asay $STDERR, Dumper $_rpc;
  $self->_sub_process if defined $_work;

}

# Create the actual process
method _sub_process {
  my $on_setup=$_[0];
  $_wid//=-1;    #ensure this is locked
  DEBUG and asay_now $STDERR, "---CALLED _subprocess in worker";
  my $__on_complete=sub {
    # unregister worker?
    $_on_complete and &$_on_complete
  };

  my $__work=sub {
    $_wid=$$; # NOTE: needed for child to know its worker id
    $0=$_name if $_name;

    asay_now $STDERR, "++++++DOING CHILD SETUP for wid $_wid";
    $self->_child_setup;
    $_work and $_work->($self);
  };

  DEBUG and asay_now $STDERR, "---Just before sub_process IO call";
  sub_process $__work, 
  sub {
    @$_io=@_;
    $_wid=$_io->[3]; #NOte this is only in parent
    #DEBUG and say STDERR "____CALLING SUB_PROCESS IN WORKER .. new id $_wid";
    if(@$_io){
      #Do parent stuff here
      #asap sub {
      $self->_parent_setup;
      $_io->[2]->pipe_to($STDERR);
      #	}
      $self->do_rpc;

    }
    else {
      # Error in parent
      #DEBUG and say STDERR "---- ERROR IN PARENT";
    }
    $on_setup and &$on_setup;
  },
  $__on_complete,
  $_on_child;
}

method eval {
  unshift @_, "eval";
  $self->rpc(@_);
}

method rpa {
  my $name=shift;
  my $string=shift;
  my $cb=shift;
  my $error=shift;
  $_active->{++$_seq}=[$cb, $error];
  $_broker->broadcast(undef,"worker/$_wid/rpa/$name", pack "La*", $_seq, $string);
  $_seq;
}

method rpc {
  
  DEBUG and asay_now $STDERR, "WORKER RPC";
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
  return if $_wid <0; # still launching
  my $e=shift @$_queue;
  DEBUG and asay $STDERR, "---WORKER RPC CALLED wid $_wid";
  my $name=shift @$e; # Name could be code ref
  my $string=shift @$e;
  my $cb=shift @$e;
  my $error=shift @$e;

  if($_rpc->{$name}){
    DEBUG and asay_now $STDERR, "WORKER id before  sub process in do_rpc $_wid";
    if($_wid){
      # just try rpc
        $_call_count++;
        $_active->{++$_seq}=[$cb, $error];
        $_broker->broadcast(undef, "worker/$_wid/rpc/$name", pack "La*" ,$_seq, $string);
    }
    else{
      # Lauch child
    $self->_sub_process(sub {
        $_call_count++;
        $_active->{++$_seq}=[$cb, $error];
        $_broker->broadcast(undef, "worker/$_wid/rpc/$name", pack "La*" ,$_seq, $string);
      }
    )
  }
    #return $_seq;
  }
  else {
    #DEBUG and say STDERR "--RPC name not in worker $name";
  }
  undef;
}



method close {
  #asay $STDERR, "---CLOSING WORKER---";
  return unless $_wid;
  $_bridge->close if $_bridge;

  sub_process_cancel $_wid;
  @$_io=();#undef;
  $_wid=undef;
  $self->_clean_up;

}

method _clean_up {
  #DEBUG and say STDERR "---- CLEAN UP WORKER----";
  #my $forward_sub=$_bridge->forward_message_sub;

  #DEBUG and asay $STDERR, Dumper $_register;
  #$_broker->ignore($_bridge->source_id, "^worker/$_wid/", $forward_sub);
  for(@$_register){
    #DEBUG and asay $STDERR, " to ignore in cleanup ".Dumper $_;
    $_broker->ignore(@$_);
  }
  $_register=[];
  $_call_count=0;
  $_broker->remove_bridge($_bridge) if $_bridge;
  DEBUG and asay $STDERR, "---- END OF CLEAN UP WORKER----";
}

# Setup child bridge to parent
method _child_setup {
  asay_now $STDERR, "-- $$ IN CHILD SETUP";
  # remove existing registrations
  $self->_clean_up;
  # If we are the result of a fork,  make sure
  DEBUG and Log::OK::TRACE and log_trace "Configuring worker (rpc) interface in child"; 
  # TODO: remove all worker registrations in broker as we are not interested in  existing working registrations
  #
  $uSAC::Main::Worker=$self;
  $STDIN->pause;
  $_bridge=uSAC::FastPack::Broker::Bridge::Streaming->new(broker=>$_broker, reader=>$STDIN, writer=>$STDOUT, rfd=>0,  wfd=>1);
  $_broker->add_bridge($_bridge);

  ##############################################################################
  # $_broker->listen(undef,".*", sub {                                         #
  #     asay_now $STDERR, "$_[0][0], $_[0][1][0][1],  --- $$ popopoipoipoioi"; #
  #   });                                                                      #
  ##############################################################################

  #$_broker->listen(undef, ".*", $_bridge);

  $_broker->listen($_bridge->source_id, "^worker/$_wid/", $_bridge->forward_message_sub);
  #$_broker->listen(undef ,"^worker/$_wid/", $_bridge->forward_message_sub);


  # Now register for messages from parent
  $_broker->listen(undef, "^worker/$_wid/rpa/(\\w+)", sub {
      DEBUG and asay $STDERR, "========== IN RPA==============";
      # Add a procedure which we can call
      #
      my $sender=shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name= $cap->[0];
        #my $seq= $cap->[1];
        my ($seq, $payload)=unpack "La*", $msg->[FP_MSG_PAYLOAD];

        local $@;
        my $sub=eval $payload;
        if($@){
          # Error.   
          my $error=Error::Show::context $@;
          $_broker->broadcast(undef,"worker/$_wid/rpa-error/$name", pack "La*", $seq, $error);
        }
        else {
          $_rpc->{$name}=$sub;
          $_broker->broadcast(undef,"worker/$_wid/rpa-return/$name", pack "La*", $seq, 1);
          DEBUG and asay $STDERR, "INSTALLED REMOTE PROCEEDURES for name $name seq $seq: ".Dumper $_rpc;
        }
      }

    });

  #$_broker->listen(undef, "^worker/$_wid/rpc/(\\w+)/(\\d+)", sub {
  $_broker->listen(undef, "^worker/$_wid/rpc/(\\w+)", sub {
      # call a procedure
      my $sender=shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name= $cap->[0];
        #my $seq= $cap->[1];
        DEBUG and asay_now $STDERR, "$$ child rpc called by name: $name";
        my $sub= $_rpc->{$name};
        #DEBUG and say STDERR "$$ child rpc sub found is $sub";
        my ($seq, $payload)=unpack "La*", $msg->[FP_MSG_PAYLOAD];
	#say STDERR $seq;
	#say STDERR $payload;
        if($sub){
          try {
            # Sequence is encoded as first 4 bytes
            #my $res=$sub->($msg->[FP_MSG_PAYLOAD]);
            my $res=$sub->($payload);
            #DEBUG and asay $STDERR, "child rpc result ". Dumper $res;
            #$_broker->broadcast(undef, "worker/$_wid/rpc-return/$name/$seq", $res);
            #$_broker->broadcast(undef, "worker/$_wid/rpc-return/$name/$seq", undef);
            DEBUG and asay_now $STDERR, "$$ return sub results to worker/$_wid/rpc-return/$name";

            $_broker->broadcast(undef, "worker/$_wid/rpc-return/$name", pack "La*", $seq, $res);
          }
          catch($e){
            my $error=Error::Show::context $e;
            #$_broker->broadcast(undef,"worker/$_wid/rpc-error/$name/$seq", $error);
            #say STDERR "$$ RPC ERROR in child----- ". $e;
            $_broker->broadcast(undef,"worker/$_wid/rpc-error/$name", pack "La*", $seq, $error);
          }
        }
        else {
          #$_broker->broadcast(undef,"worker/$_wid/rpc-error/$name/$seq", "RPC NOT FOUND");
          $_broker->broadcast(undef,"worker/$_wid/rpc-error/$name", pack "La*", $seq,"RPC NOT FOUND");
        }
      }
      #$_broker->clear_cache;
    });


  my $sub;
  $sub= sub {
    use feature 'state';
    state $i=0;
    DEBUG and asay $STDERR, "--- $$ TIMER IN CHILD WORKER $i -----";
    $_broker->broadcast(undef, "worker/$_wid/status", pack "La*", $i, "Hello from $_wid");
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
  #DEBUG and say STDERR "PARENT SETUP "."@$_io";
  $_bridge=uSAC::FastPack::Broker::Bridge::Streaming->new(broker=>$_broker, reader=>$_io->[1], writer=>$_io->[0], rfd=>$_io->[1]->fh,  wfd=>$_io->[0]->fh);

  #DEBUG and say STDERR "PARENT SETUP after bridge";
  my $forward_sub=$_bridge->forward_message_sub;
  $_broker->add_bridge($_bridge);

  ########################################################################################
  # $_broker->listen(undef,".*", sub {                                                   #
  #     asay_now $STDERR, "$_[0][0], $_[0][1][0][1],  --- $$ jkasdfjasdl;kjasd;lkjasdf"; #
  #   });                                                                                #
  ########################################################################################
  #$_broker->listen(undef, ".*", $_bridge);
  my $r;
  # Listen for any local messages and forward to other end of bridge
  #
  $r=[$_bridge->source_id, "^worker/$_wid/", $forward_sub];

  #say STDERR " ABOUT TO REGISTER LISTENERS forwarder for wid $_wid, bridge id @{[$_bridge->source_id]}";
  $_broker->listen(@$r);
  push @$_register, $r;
  #$_broker->listen(undef, "^worker/$_wid/", $forward_sub);
  
  #$r=[undef, "^worker/$_wid/rpa-return/(\\w+)/(\\d+)\$", sub {
  $r=[undef, "^worker/$_wid/rpa-return/(\\w+)\$", sub {
      asay_now $STDERR, "--- $$ GOT RPC RETURN IN PARENT-worker";
      shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name=$cap->[0];
        #my $i=$cap->[1];   
        my ($i,$payload)=unpack "La*", $msg->[FP_MSG_PAYLOAD];
        #DEBUG and say STDERR "RPA RETURN----- $_wid  $name";
        my $e=delete $_active->{$i};
        #$e->[0] and $e->[0]->($msg->[FP_MSG_PAYLOAD]);
        $e->[0] and $e->[0]->($payload);
      }
    }];
  # Add RPA support
  #DEBUG and say STDERR " ABOUT TO REGISTER LISTENERS rpa";
  $_broker->listen(@$r);
  push @$_register, $r;

  $r=[
    #undef, "^worker/$_wid/rpa-error/(\\w+)/(\\d+)\$", sub {
    undef, "^worker/$_wid/rpa-error/(\\w+)\$", sub {
      shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name=$cap->[0];
        #my $i=$cap->[1];   
        my ($i,$payload)=unpack "La*", $msg->[FP_MSG_PAYLOAD];
        DEBUG and asay $STDERR, "RPA ERROR----- $_wid  $name";
        my $e=delete $_active->{$i};
        #$e->[0] and $e->[0]->($msg->[FP_MSG_PAYLOAD]);
        $e->[0] and $e->[0]->($payload);
      }

    }
  ];
  #DEBUG and say STDERR " ABOUT TO REGISTER LISTENERS rpa-error";
  $_broker->listen(@$r);
  push @$_register, $r;
  $r=[
    #undef, "^worker/$_wid/rpc-return/(\\w+)/(\\d+)\$", sub {
    undef, "^worker/$_wid/rpc-return/(\\w+)\$", sub {
      DEBUG and asay_now $STDERR, "$$ RPC RETURN in server for worker $self  $_wid ----- ". Dumper @_;
      shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name=$cap->[0];
        #my $i=$cap->[1];   
        my ($i,$payload)=unpack "La*", $msg->[FP_MSG_PAYLOAD];
        #DEBUG and say STDERR "RPC RETURN----- $_wid  $name";
        my $e=delete $_active->{$i};

        #$_broker->broadcast(undef,"worker/$_wid/rpc/$name/$i", undef);
        if($_shrink_mask and $_call_count >= $_call_max){
          #DEBUG and say STDERR "=======MAX CALL COUNT REACHED";
          $self->_clean_up;
          $self->close;
        }
        elsif(@$_queue == 0 and $_shrink and $_shrink_mask){
          #DEBUG and say STDERR "============Closing worker as queue is empty";
          $self->_clean_up;
          $self->close;
        }

        #DEBUG and say STDERR "======= about to do callback ", $e;
	$e->[0] and $e->[0]->($payload);
	#$e->[0] and asap $e->[0], $payload;
	#$_broker->clear_cache;
        $self->do_rpc;
      }
    }
  ];

  # Add RPC support
  #DEBUG and say STDERR " ABOUT TO REGISTER LISTENERS rpc-return";
  $_broker->listen(@$r);
  push @$_register,$r;

  $r=[
    #undef, "^worker/$_wid/rpc-error/(\\w+)/(\\d+)\$", sub {
    undef, "^worker/$_wid/rpc-error/(\\w+)\$", sub {
      #asay $STDERR, "$$ RPC ERROR in server----- ". Dumper @_;
      shift $_[0]->@*;
      for my ($msg, $cap)($_[0][0]->@*){
        my $name=$cap->[0];
        #my $i=$cap->[1];   
        my ($i,$payload)=unpack "La*", $msg->[FP_MSG_PAYLOAD];
        #DEBUG and say STDERR "RPC ERROR----- $_wid  $name $payload";#$msg->[FP_MSG_PAYLOAD]";
        my $e=delete $_active->{$i};
        #$e->[1] and $e->[1]->($msg->[FP_MSG_PAYLOAD]);
        $e->[1] and $e->[1]->($payload);
      }
    }
  ];
  #DEBUG and say STDERR " ABOUT TO REGISTER LISTENERS rpc-error";
  $_broker->listen(@$r);
  push @$_register, $r;


  #$_io->[2]->pipe_to($STDERR);


  

  # Now register for messages from worker
  #
  $r=[
    undef, "^worker/$_wid/status\$", sub {
      # Strip all but the payload
      #asay_now $STDERR, "$$ got worker status ";
      $_on_status and $_on_status->($_[0][1][0][2]);

    }
  ];

  $_broker->listen(@$r);
  push @$_register, $r;

  # Now register for messages from worker
  #
  $r=[
    undef, "^worker/$_wid/results/\$", sub {
      # Strip all but the payload
      $_on_result and $_on_result->($_[0][1][0][2]);
    }
  ];

  $_broker->listen(@$r);
  push @$_register, $r;
  

  ################################################
  # asay $STDERR, "--SETUP UP PARENT TIMER=---"; #
  # my $t = timer 1, 0, sub {                    #
  #   asay $STDERR, "--PARENT TIMER--";          #
  # };                                           #
  ################################################
}


method report {
    use feature 'state';
    state $i=0;
    return unless $_[0];
    #$_broker->broadcast(undef, "worker/$_wid/results", pack "La*", $i, $_[0]);
    $i++;
}

method status {
    use feature 'state';
    state $i=0;
    return unless $_[0];
    #$_broker->broadcast(undef, "worker/$_wid/status", pack "La*", $i, $_[0]);
    $i++;
}

1;
