package uSAC::DIO::AE::DIO;
use strict;
use warnings;
use version; our $VERSION=version->declare("v0.1");

use feature qw<say state refaliasing>;
use Socket qw<AF_INET SOCK_STREAM SOCK_DGRAM pack_sockaddr_in inet_aton>;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use Errno qw(EAGAIN EINTR EINPROGRESS);
use Carp qw<carp>;

use AnyEvent;


use Exporter qw<import>;

our @EXPORT_OK=qw<connect_inet bind_inet>;
our @EXPORT=@EXPORT_OK;

#Does a bind on the socket
sub bind_inet {
        my ($host, $port, $on_connect, $on_error)=@_;
        $on_connect//=sub{};
        $on_error//=sub{};

        socket my $fh, AF_INET, SOCK_DGRAM, 0;

        fcntl $fh, F_SETFL, O_NONBLOCK;

        my $addr=pack_sockaddr_in $port, inet_aton $host;

	my $res=bind 	$fh, $addr;
        unless($res){
		warn "Could not bind";
		#$self->[on_error_]();
		AnyEvent::postpone {
			$on_error->($!);
		};
		return;
        }
        AnyEvent::postpone {$on_connect->($fh)};

}

sub connect_inet {
        my ($host,$port,$on_connect,$on_error)=@_;

        $on_connect//=sub{};
        $on_error//=sub{};

        socket my $fh, AF_INET, SOCK_DGRAM, 0;

        fcntl $fh, F_SETFL, O_NONBLOCK;

        my $addr=pack_sockaddr_in $port, inet_aton $host;

	my $local=pack_sockaddr_in 0, inet_aton "0.0.0.0";
        #Do non blocking connect
        #A EINPROGRESS is expected due to non block
        ################################
        # unless(bind $fh, $local){    #
        #         say "bind error $!"; #
        # }                            #
        ################################
	my $res=connect $fh, $addr;
        unless($res){
                #EAGAIN for pipes
                if($! == EAGAIN or $! == EINPROGRESS){
                        say " non blocking connect";
                        my $cw;$cw=AE::io $fh, 1, sub {
                                #Need to check if the socket has
                                my $sockaddr=getpeername $fh;
                                undef $cw;
                                if($sockaddr){
                                        $on_connect->($fh);
                                }
                                else {
                                        #error
                                        say $!;
                                        $on_error->($!);
                                }
                        };
                        return;
                }
                else {
                        say "Error in connect";
                        warn "Counld not connect to host";
                        #$self->[on_error_]();
                        AnyEvent::postpone {
                                $on_error->($!);
                        };
                        return;
                }
                return;
        }
        AnyEvent::postpone {$on_connect->($fh)};
}

1;


