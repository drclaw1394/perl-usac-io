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

use IO::Socket::IP '-register';


use Exporter;# qw<import>;

sub import {
	#Export all symbols in sock
	@_=(":all");
	goto &IO::Socket::import;

}

#asynchronous bind for tcp, udp, and unix sockets

use uSAC::IO::Common;
my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::IO");
say $rb;

unless(eval "require $rb"){
	say "ERROR IN REQUIRE";
	say $@;
}


sub bind{
	my $package=shift;

	#say "bind".$_[0];
	my @stat=stat $_[0];
	say join ", ",@stat;
	my $fam= sockaddr_family getsockname $_[0];
	say "sockdomain ".$_[0]->sockdomain;
	say "Family: $fam";
	say unpack "I*", $fam;
	say "AF_INET:".AF_INET;
	say "AF_INET6:".AF_INET6;
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
	#say "bind".$_[0];
	my @stat=stat $_[0];
	say join ", ",@stat;
	my $fam= sockaddr_family getsockname $_[0];
	die  "Not a socket" unless defined $fam;
	if($fam==AF_INET){
		say  "calling inet with: ",@_;
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
	say "Called with: ",join ", ",@_;
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


sub dreader {
	shift;
	uSAC::IO::DReader->dreader(@_);
}
sub sreader {
	shift;
	uSAC::IO::SReader->sreader(@_);
}

sub dwriter {
	shift;
	uSAC::IO::DWriter->dwriter(@_);
}
sub swriter {
	shift;
	uSAC::IO::SWriter->swriter(@_);
}




sub writer {
	my $package=shift;

	say "Inputs: ",@_;
	say "WRiter: ".$_[1];
	my @stat=stat $_[1];
	say join ", ",@stat;
	if(-p $_[1]){
		say "PIPE FH";
		return $package->swriter(@_);		
	}
	elsif(-S $_[1]){
		say "SOCKET FH";
		for(unpack "I", getsockopt $_[1], SOL_SOCKET, SO_TYPE){
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
		say "DIFFERT TYPE";
		return $package->swriter(@_);		
	}
}

sub reader{
	my $package=shift;
	say "inputs: ",@_;
	say "reader: ".$_[1];
	my @stat=stat $_[1];
	say join ", ",@stat;
	if(-p $_[1]){
		say "PIPE FH";
		return $package->sreader(@_);		
	}
	elsif(-S $_[1]){
		say "SOCKET FH";

		for(unpack "I", getsockopt $_[1], SOL_SOCKET, SO_TYPE){
			#say "SOCK_STREAM: ".SOCK_STREAM;
			#say unpack "H*",$_;
			#say unpack "I",$_;
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
		say "DIFFERT TYPE";
		return $package->sreader(@_);		
	}
}

1;
