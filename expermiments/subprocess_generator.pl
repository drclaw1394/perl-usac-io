# large amounts of Data is generated from non stream
use v5.36;
use uSAC::IO;
use uSAC::Log;
#use uSAC::FastPack::Broker;
use Data::Dumper;


my $cmd="zip  -0 - Changes";
(undef, my $read, undef, my $pid) = uSAC::IO::sub_process $cmd, sub {
  asay $STDERR, "Process completed handler @_";
};
$uSAC::Main::listener->(undef, "results/ls", sub {
    #print Dumper @_;
    #log_info "DF".$_[0][1][0][2];
    #print  $_[0][1][0][2];
    $uSAC::IO::STDOUT->write([$_[0][1][0][2]], sub {
      $read->start;
    })
});

$read->on_read= sub {
  $read->pause;
  state $i=0;
  $i++;
  #$_[0][0]=uc $_[0][0];
  $uSAC::Main::broadcaster->("results/ls", $_[0][0]);
  $_[0][0]="";
};

$read->on_eof= sub {

  asay $STDERR, "on eof";
  sub_process_cancel $pid;
};


$read->start;




