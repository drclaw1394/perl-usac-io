#!/usr/bin/env usac --backend AnyEvent

use v5.36;
use uSAC::IO;
use IO::FD;
use Fcntl;

my $buffer="";
my $fd=IO::FD::sysopen(my $fd, "/dev/random", O_RDONLY);
my $reader=reader $fd;
my $i=0;
$reader->on_read=sub {asay length $_[0][0]; $_[0][0]=""; exit if $i>100000; $i++};
$reader->start;
