package uSAC::IO::AE::IO;

use strict;
use warnings;
use feature "say";

use Socket qw<AF_INET AF_INET6 AF_UNIX pack_sockaddr_in pack_sockaddr_in6 pack_sockaddr_un>;
use Errno qw(EAGAIN EINTR EINPROGRESS);
use parent "uSAC::IO";

use AnyEvent;

sub new {
	my $package=shift;
	$package->SUPER::new(@_);
}

sub bind {
	my ($package, $socket, $addr, $on_bind, $on_error)=@_;
	unless(CORE::bind $socket, $addr){
		$on_error->($!) if $on_error;
	}
	$on_bind->($socket, $addr) if $on_bind;
	$addr;
}

sub connect {
        #A EINPROGRESS is expected due to non block
        my ($package, $socket, $addr, $on_connect, $on_error)=@_;

	say "In connect: ".unpack "H*", $addr;
	my $res=CORE::connect $socket, $addr;
        unless($res){
                #EAGAIN for pipes
                if($! == EAGAIN or $! == EINPROGRESS){
                        say " non blocking connect";
                        my $cw;$cw=AE::io $socket, 1, sub {
                                #Need to check if the socket has
                                my $sockaddr=getpeername $socket;
                                undef $cw;
                                if($sockaddr){
                                        $on_connect->($socket) if $on_connect;
                                }
                                else {
                                        #error
                                        $on_error and $on_error->($!);
                                }
                        };
                        return;
                }
                else {
                        say "Error in connect";
                        warn "Counld not connect to host";
                        $on_error and AnyEvent::postpone {
                                $on_error->($!) 
                        };
                        return;
                }
                return;
        }
        AnyEvent::postpone {$on_connect->($socket)} if $on_connect;
}
1;
