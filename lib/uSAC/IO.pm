package uSAC::IO;
use strict;
use warnings;
use feature "say";

#Datagram
use uSAC::IO::DReader;
use uSAC::IO::DWriter;

#Stream
use uSAC::IO::SWriter;
use uSAC::IO::SReader;

use Socket  ":all";

#use IO::Socket::IP '-register';


use Exporter;# qw<import>;

sub import {
	Socket->export_to_level(1, undef, ":all");

}

#asynchronous bind for tcp, udp, and unix sockets

use uSAC::IO::Common;
my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::IO");

die "Could not require $rb" unless(eval "require $rb");


sub socket {
	my ($package, $fam, $type, $proto)=@_;
	my $socket;
	CORE::socket $socket,$fam, $type, $proto;
	$socket;
}

sub bind{
	my $package=shift;

	my @stat=stat $_[0];
	my $fam= sockaddr_family getsockname $_[0];
	die  "Not a socket" unless defined $fam;
	if($fam==AF_INET){
		return $package->bind_inet(@_);		
	}
	elsif($fam==AF_INET6){
		return $package->bind_inet6(@_);		
	}
	elsif($fam==AF_UNIX){
		return $package->bind_unix(@_);		
	}
	else {
		die "Unsupported socket address family";
	}
}
sub connect{
	my $package=shift;
	my @stat=stat $_[0];
	my $fam= sockaddr_family getsockname $_[0];
	die  "Not a socket" unless defined $fam;
	if($fam==AF_INET){
		return $package->connect_inet(@_);		
	}
	elsif($fam=AF_INET6){
		return $package->connect_inet6(@_);		
	}
	elsif($fam==AF_UNIX){
		return $package->connect_unix(@_);		
	}
	else {
		die "Unsupported socket address family";
	}
}

sub bind_inet {
	my ($package, $socket, $host, $port, $on_bind, $on_error)=@_;
	#get the socket type
	my $fam= sockaddr_family getsockname $socket;

	$on_error and !$fam and $on_error->("Socket does not match address family");
	!$on_error and !$fam and die "Socket does not match address family";

	my $a= inet_pton AF_INET, $host;
	$on_error and !$a and return $on_error->("Address ill formated");
	!$on_error and !$a and die "Address ill formated";

	my $addr=pack_sockaddr_in $port,$a;
	(ref($package)||$rb)->bind($socket, $addr, $on_bind, $on_error);
}


sub bind_inet6 {
	my ($package, $socket,$host,$port,$scope_id,$flow_info, $on_bind, $on_error)=@_;
	#get the socket type
	my $fam= sockaddr_family getsockname $socket;
	$on_error and !$fam and $on_error->("Socket does not match address family");
	!$on_error and !$fam and die "Socket does not match address family";

	my $a= inet_pton(AF_INET6, $host);
	$on_error and !$a and return $on_error->("Address ill formated");
	!$on_error and !$a and die "Address ill formated";

	my $addr=pack_sockaddr_in6 $port, $a, $scope_id, $flow_info;
	(ref($package)||$rb)->bind($socket, $addr, $on_bind, $on_error);
}


sub bind_unix {
	my ($package, $socket,$path, $on_bind, $on_error)=@_;
	#get the socket type
	my $fam= sockaddr_family getsockname $socket;
	$on_error and !$fam and $on_error->("Socket does not match address family");
	!$on_error and !$fam and die "Socket does not match address family";

	my $addr=pack_sockaddr_un $path;
	(ref($package)||$rb)->bind($socket, $addr, $on_bind, $on_error);
}

#CONNECT
sub connect_inet {
        my ($package, $socket, $host, $port, $on_connect,$on_error)=@_;
        my $addr=pack_sockaddr_in $port, inet_pton AF_INET, $host;
	(ref($package)|| $rb)->connect($socket, $addr, $on_connect, $on_error);
}

sub connect_inet6 {
        my ($package, $socket, $host, $port, $on_connect, $on_error)=@_;
        my $addr=pack_sockaddr_in6 $port, inet_pton AF_INET6, $host;
	(ref($package)||$rb)->connect($socket, $addr, $on_connect, $on_error);
}

sub connect_unix {
        my ($package, $socket, $path, $on_connect, $on_error)=@_;
        my $addr=pack_sockaddr_un $path;
	(ref($package)||$rb)->connect($socket, $addr, $on_connect, $on_error);
}
sub cancel_connect {
	my $package=shift;
	(ref($package)||$rb)->cancel_connect(@_);
}


sub dreader {
	shift;
	uSAC::IO::DReader->create(@_);
}
sub sreader {
	shift;
	uSAC::IO::SReader->create(@_);
}

sub dwriter {
	shift;
	uSAC::IO::DWriter->create(@_);
}
sub swriter {
	shift;
	uSAC::IO::SWriter->create(@_);
}




sub writer {
	my $package=shift;

	my @stat=stat $_[0];
	if(-p $_[0]){
		return $package->swriter(@_);		
	}
	elsif(-S $_[1]){
		for(unpack "I", getsockopt $_[0], SOL_SOCKET, SO_TYPE){
			if($_==SOCK_STREAM){
				return $package->swriter(@_);		
			}
			elsif($_==SOCK_DGRAM){
				return $package->dwriter(@_);		
			}
			elsif($_==SOCK_RAW){
				die "RAW SOCKET NOT IMPLEMENTED";
			}
			else {
				die "Unkown socket type";
			}
		}
	}
	else {
		#TODO: fix this
		return $package->swriter(@_);		
	}
}

sub reader{
	my $package=shift;
	my @stat=stat $_[0];
	if(-p $_[0]){
		return $package->sreader(@_);		
	}
	elsif(-S $_[0]){

		for(unpack "I", getsockopt $_[0], SOL_SOCKET, SO_TYPE){
			if($_ == SOCK_STREAM){
				return $package->sreader(@_);		
			}
			elsif($_ == SOCK_DGRAM){
				return $package->dreader(@_);		
			}
			elsif($_ == SOCK_RAW){
				die "RAW SOCKET NOT IMPLEMENTED";
			}
			else {
				die "Unkown socket type";
			}
		}
	}
	else {
		#TODO: fix this
		return $package->sreader(@_);		
	}
}

sub pair {
	my ($package, $fh)=@_;
	my ($r,$w)=($package->reader(fh=>$fh), $package->writer(fh=>$fh));
	$r and $w ? ($r,$w):();
}

sub pipe {
	my ($package, $rfh,$wfh)=@_;
	my ($r,$w)=($package->reader($rfh), $package->writer($wfh));
	if($r and $w){
		$r->pipe($w);
		return ($r,$w);	
	}
	();
	
}

1;
