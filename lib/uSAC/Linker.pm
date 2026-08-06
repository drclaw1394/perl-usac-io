package uSAC::Linker;

use v5.36;

use uSAC::IO;
use Data::FastPack::Meta;
use constant::more DEBUG=>1;

# Provides common links and a way to link them Asynchronouse
# processing with out promises and works with multiple runs
#
#
#
use Sub::Middler;
use Export::These qw<io_backtick io_lines io_accumulate io_grep io_filter io_upper io_lower
io_file_open
io_file_slurp
io_file_spurt
linker
>;

sub io_map :prototype($){
  my $filter=shift;
  sub {
    my ($next, $index, @options)=@_;
    sub {
      #my $cb=$_[$#_];
      @{$_[0]}= map $filter->($_), @{$_[0]};
      &$next;
    }
  }
}

#synchronous

#Inplace
sub io_grep :prototype($){
  my $filter=$_[0];
  sub {
    my ($next)=@_;
    sub {
      @{$_[0]}= grep $_=~ $filter, @{$_[0]};
      &$next;
    }
  }
}

# Inplace
sub io_filter :prototype($){
  my $filter=$_[0];
  sub {
    my ($next)=@_;
    sub {
      @{$_[0]}= grep $_=~ $filter, @{$_[0]};
      &$next;
    }
  }
}

#synchronous
#Modify inputs
sub io_upper :prototype(){
  sub {
    my ($next, $index, @options)=@_;
    sub {
      for my($s)(@{$_[0]}){
        $s=uc $s; 
      }
      &$next;
    }
  }
}

sub io_lower :prototype(){
  sub {
    my ($next, $index, @options)=@_;
    sub {
      for my($s)(@{$_[0]}){
        $s=lc $s; 
      }
      &$next;
    }
  }
}

#synchronous
#consumes input
sub io_lines {
  my $sep=shift//$/; # save input seperator
  my $slen=length $sep;
  my $buffer=""; # buffing
  sub {
    my ($next, $index, @options)=@_;
    sub {
      my @lines;

      # expects last element as a callback, if  no callback is last data
      my $cb=$_[$#_];

      # Alias of in put means consumed in place 
      #
      my $idx;
      for(@{$_[0]}){
        while(($idx=index $_, $sep)>=0){
          # found sep
          if($buffer){
            push @lines, $buffer.substr $_, 0, $idx, ""; #extract line
            $buffer="";
          }
          else {
            push @lines, substr $_, 0, $idx, ""; #extract line
          }
          substr $_, 0, $slen,""; #//Strip sep
        }
        # accumulate remainder to buffer
        $buffer.=$_;
      }

      if($cb){
        $cb->();
      }
      else{
        # Add the remainder if last call
        push @lines, $buffer;
        $next->(\@lines, $cb);
      }
    }
  }
}


# return accumulated results from stdout
# consumes input
sub io_accumulate {
  my $buffer=[""];
  sub {
    my ($next, $index, @options)=@_;
    sub {
      my $cb=pop;
      # Consume input, but leave array
      $buffer->[0] .= pop $_[0]->@* for @{$_[0]};

      
      # Call next with no callback provided. Marks end or data
      if($cb){
        #Do callback to indicate data is consumed;
        $cb->();
      }
      else {
        # No more data (no cb) so finish it
        $next->($buffer, $cb)
      }
    }
  }
}

# Copy the input argument. Prevents future operations form modifiing input data
# INPUTS are left unchanged
sub io_copy {
  my @buffer;
  sub {
    my ($next, $index, @options)=@_;
    sub {
      my $cb=pop;
      @buffer= $_[0]->@*;

      # Call next with no callback provided. Marks end or data
      $next->(\@buffer, $cb) unless $cb;
    }
  }
}

# The inputs are consumbed by any middleware next in the normal chain
# The iputs are copied for each of the tees.
# Tees are run asynchrounously
#
sub io_tee {
  my @tees=@_;
  my @buffers;

  for(@tees){
    push @buffers, [];
  }

  sub {
    my ($next, $index, @options)=@_;
    sub {
      my $cb=$_[1];
      # tees are schedualed
      for(0..@tees-1){
        # Copy inputs to each of the buffers
        push $buffers[$_]->@*, $_[0]->@*;
        asap($tees[$_], $buffers[$_], $cb);
      }

      # Call next syncrhonously
      &$next;
    }
  }

}

sub io_backtick {
  my $cmd=shift;
  my $on_result=shift;
  my $buffer="";
  my $status;
  my $pid;

  my @io;
  my $join=0;

  sub {
    my ($next, $index, @options)=@_;
    sub  {
      my $cb=pop;
      my $do_result=sub {
        $join++;
        return if $join < 2;
        # Close the io


        IO::FD::close($io[0]->fh);
        $io[0]->destroy();
        IO::FD::close($io[1]->fh);
        $io[1]->destroy();
        IO::FD::close($io[2]->fh);
        $io[2]->destroy();

        $next->([$buffer], $cb);
      };

      my $tmp=$_[0]//[];
      sub_process "$cmd $tmp->@*"; 
      sub {
        # parent continuation
        @io=@_;

        $pid=$io[3];

        # Back tick handles stadard out only
        $io[1]->on_read=sub {
          $buffer.=$_[0][0]; $_[0][0]="";
        };

        $io[1]->on_eof=sub {
          $do_result->();
        };


        # Consume the error stream
        $io[2]->on_read=sub {
          $_[0][0]="";
        };

        # Start readers
        $io[1]->start;
        $io[2]->start;

        # return the pid of th child process
        #$io[3];
        $pid;

      },
      sub {
        # On child cpmplete
        my $a=shift;

        # Save the status and pid of the process. We might have a reading to do however
        ($status, $pid)=$a->@*;
        $do_result->();

      };

    }
  }
}

# Open files
sub io_file_open {
  my ($fid, $error)=@_;

  #adump $STDERR, "io_file_open_wrapper";

  my $pool=uSAC::IO::_make_pool;
  sub {
    my ($next, $index, @options)=@_;
    #adump $STDERR, "io_file_open_linker ", @_;
    sub {
      #adump $STDERR, "io_file_open";
      my $cb=$_[$#_];
      my $enc=encode_meta_payload $_[0], 1;
      my $__cb=sub {
        DEBUG and adump $STDERR, "$$ Callback in file_open", @_;
        my $p=decode_meta_payload $_[0], 1;


        # call next with generated fid
        $$fid=$p->{fid};
        DEBUG and adump $STDERR, "$$ Callback in file_open", $p;
        $next->([], $cb);
      };

      # Call sticky_rpc
      $pool->sticky_rpc("file_open", $enc, $__cb, $error);
    }
  }
}

sub io_file_close {
  my ($fid, $error)=@_;
  my $pool=uSAC::IO::_make_pool; 
  sub {
    my ($next, $index, @options)=@_;
    sub {
      #adump $STDERR, "io_file_close";
      # First argument is the fid, remainder is data
      #close the file and call next, Only Close the file if NO CALLBACK is
      &$next if $_[1];

      my $cb=$_[$#_];

      #specified
      my $args=$_[0];
        $_[0]=[];
      my $enc=encode_meta_payload [{fid=>$$fid}], 1;
      my $__cb=sub {

        DEBUG and asay $STDERR, "$$ Callback in file_close";
        my $p=decode_meta_payload $_[0], 1;

        $$fid=undef;
        $next->($args, my $c=undef);
      };
      $pool->sticky_rpc("file_close", $enc, $__cb, $error);
    }
  }
}

#link  file_read, $accumulate $dispatch
sub io_file_read {
  my ($fid,  $error)=@_;
  my $pool=uSAC::IO::_make_pool;
  sub {
    my ($next, $index, @options)=@_;
      # Setup variables to allow callback to read more from file
      my $__cb;
      my $enc;
      my $__wid;
      my $internal_cb=sub {
        $pool->sticky_rpc("file_read", $enc, $__cb, $error, $__wid);
      };
      $__cb=sub {
        DEBUG and say STDERR "$$ Callback in file_read";
        my $p=decode_meta_payload $_[0], 1;
        #$cb->($p);
        if($p->{rc}){
          #say STDERR "RC non zero. call internal";
          $next->($p->{data}, $internal_cb);
        }
        else {

          #say STDERR "RC zero. call normal callback?";
          $__wid=undef;
          $next->($p->{data}, my $c=undef);
        }
      };

    sub {
      #say STDERR "io_file_read";
      
      unless($__wid){
        # Decode sthe file id once
        $__wid=unpack "L", $$fid;
      #my $cb=$_[$#_];
        $enc=encode_meta_payload [{fid=>$$fid}], 1;
      }
      #$internal_cb->();
      $pool->sticky_rpc("file_read", $enc, $__cb, $error, $__wid);
    }
  }
}

sub io_file_write{
  my ($fid, $error)=@_;
  my $pool=uSAC::IO::_make_pool;
  sub {
    my ($next, $index, @options)=@_;
    sub {
      my $cb=$_[$#_];
      my $enc=encode_meta_payload {fid=>$$fid, data=>$_[0]}, 1;
      my $__cb=sub {
        DEBUG and asay $STDERR, "$$ Callback in file_write";
        my $p=decode_meta_payload $_[0], 1;
        #$cb->($p)
        $next->($p, $cb);
      };
      $pool->rpc("file_write", $enc, $__cb, $error);
    } 
  }
}


sub io_file_slurp {
  my ($error)=@_;
  my $fid="";
  (
    io_file_open (\$fid, $error),
    io_file_read (\$fid, $error),   # uses the id from file open
    #io_accumulate,   
    io_file_close (\$fid, $error),
  )
}

sub io_file_spurt {
  my ($path, $cb, $error)=@_;
  # open
  # write by chunks
  # execute callback
}


1;



