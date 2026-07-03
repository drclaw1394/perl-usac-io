use v5.36;
use uSAC::IO;

asay $STDERR, "=-=-=-=-=-=-=-=-=-=-= TOP -=-=-=-=-=-=-=-=-==-=-==-";
my $worker=uSAC::Worker->new(rpc=>{
  testing=>sub {456}});

  $worker->rpc("testing", 123, sub {
    adump $STDERR, "doing testing rpc=======-=-=-=-=-=-=-=-==-=-=-==-", @_;
  }

);




