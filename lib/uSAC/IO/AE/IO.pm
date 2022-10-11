package uSAC::IO::AE::IO;

use strict;
use warnings;
use feature "say";

use Socket ":all";#qw<AF_INET AF_INET6 AF_UNIX pack_sockaddr_in pack_sockaddr_in6 pack_sockaddr_un>;
use Errno qw(EAGAIN EINTR EINPROGRESS);
use parent "uSAC::IO";

use AnyEvent;
#use IO::FD::DWIM ":all";
use IO::FD;

my %watchers;
my $id;
sub connect {
        #A EINPROGRESS is expected due to non block
        my ($package, $socket, $addr, $on_connect, $on_error)=@_;

	$id++;
	my $res=IO::FD::connect $socket, $addr;
        unless($res){
                #EAGAIN for pipes
                if($! == EAGAIN or $! == EINPROGRESS){
                        my $cw;$cw=AE::io $socket, 1, sub {
                                #Need to check if the socket has
                                my $sockaddr=IO::FD::getpeername $socket;

				delete $watchers{$id};

                                if($sockaddr){
                                        $on_connect->($socket) if $on_connect;
                                }
                                else {
                                        #error
                                        $on_error and $on_error->($!);
                                }
                        };
			$watchers{$id}=$cw;
                        return;
                }
                else {
                        warn "Counld not connect to host";
                        $on_error and AnyEvent::postpone {
                                $on_error->($!) 
                        };
                        return;
                }
                return;
        }
        AnyEvent::postpone {$on_connect->($socket)} if $on_connect;
	$id;
}

sub cancel_connect{
	my ($package,$id)=@_;
	delete $watchers{$id};
}

#take a hostname and resolve it
my $resolve_watcher;
sub resolve {
#####################################################################################
#         unless($resolve_watcher){                                                 #
#                                                                                   #
#                 my $dns = Net::DNS::Native->new(pool => 1, notify_on_begin => 1); #
# my $handle = $dns->inet_aton("google.com");                                       #
# my $sel = IO::Select->new($handle);                                               #
# $sel->can_read(); # wait "begin" notification                                     #
# sysread($handle, my $buf, 1); # $buf eq "1", $handle is not readable again        #
# $sel->can_read(); # wait "finish" notification                                    #
# # resolving done                                                                  #
# # we can sysread($handle, $buf, 1); again and $buf will be eq "2"                 #
# # but this is not necessarily                                                     #
# my $ip = $dns->get_result($handle);                                               #
#####################################################################################
	
}

sub accept {

}
sub cancel_accept {

}
1;
