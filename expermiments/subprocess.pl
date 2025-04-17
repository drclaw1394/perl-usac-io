use v5.36;
use uSAC::IO;
use uSAC::Log;
use uSAC::FastPack::Broker;
use Data::Dumper;

usac_listen(undef, "results/ls", sub {
    #print Dumper @_;
    usac_log_info $_[0][1][0][2];
});

(undef, my $read, undef, my $pid) = uSAC::IO::_sub_process "ls", sub {
  asay "Process completed handler @_";
};

$read->on_read= sub {
  state $i=0;
  $i++;
  $_[0][0]=uc $_[0][0];
  usac_broadcast("results/ls", $_[0][0]);
  $_[0][0]="";
};


$read->start;




