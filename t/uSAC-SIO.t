use strict;
use warnings;
use feature qw<refaliasing current_sub say>;

use AnyEvent;
use Test::More tests => 1;
use uSAC::SReader;
BEGIN { use_ok('uSAC::SIO') };

##################################################
# my $cv=AE::cv;                                 #
# #read from stdin test                          #
# my $reader=uSAC::SReader->new(undef, \*STDIN); #
# \my $o=\$reader->on_read;                      #
# $o=sub {                                       #
#         print "Got data: $_[1]\n"; $_[1]="";   #
# };                                             #
#                                                #
# $reader->on_eof=sub {                          #
#         print "End of input";                  #
#                                                #
#         $cv->send;                             #
# };                                             #
# $reader->start;                                #
# $cv->recv;                                     #
##################################################
