#!/usr/bin/env usac -Ilib --backend AnyEvent
# read input and execute
use feature ":all";
#use uSAC::IO;
use Data::Dump::Color;
use Error::Show;

my $reader= uSAC::IO::reader fileno(STDIN); 
my $line="";

$reader->on_read=sub {
  local $@="";
  my @res=eval $_[0];
  if($@){
    say "ERROR: $@";
    say Error::Show::context error=>$@, program=>$_[0];
  }
  else {
    dd @res;
  }
  $_[0]="";
};

$reader->start;
