package uSAC::SIO;
use strict;
use warnings;
use version; our $VERSION=version->declare("v0.1");

use uSAC::SReader;
use uSAC::SWriter;

##########################################################
# #Core                                                  #
# use Symbol 'gensym';                                   #
# use IPC::Open3;                                        #
#                                                        #
# #CPAN                                                  #
#                                                        #
# use uSAC::SReader;                                     #
# use uSAC::SWriter;                                     #
#                                                        #
# sub open_child {                                       #
#         my ($cmd, $on_child, $on_error)=@_;            #
#         my $err=gensym;                                #
#         my $pid=open3(my $poci, my $copi, $err, $cmd); #
#         if(defined $pid){                              #
#                 AE::child $pid, sub {                  #
#                         #close                         #
#                         $on_child;                     #
#                 }                                      #
#         }                                              #
# }                                                      #
##########################################################
1;

__END__
=head1 NAME

uSAC::SIO

=head1 ABSTRACT

uSAC::SIO - Streamlined Socket IO with AnyEvent



=cut
