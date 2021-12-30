package uSAC::SIO;
use strict;
use warnings;
use version; our $VERSION=version->declare("v0.1");

use uSAC::SReader;
use uSAC::SWriter;

use enum qw<sreader_ swriter_ writer_ fh_>;

sub new {
	my $package=shift//__PACKAGE__;
	my $self=[];
	my $ctx=shift;
	my $fh=shift;

	my %options=@_;

	my $sreader=uSAC::SReader->new($ctx, $fh);
	my $swriter=uSAC::SWriter->new($ctx, $fh);
	bless $self, $package;
}

sub on_error : lvalue {

}

sub on_read : lvalue {

}
sub on_eof : lvalue {

}

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
