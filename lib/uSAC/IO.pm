package uSAC::IO;
use strict;
use warnings;
use feature "say";

use Data::Dumper;
#Datagram
use uSAC::IO::DReader;
use uSAC::IO::DWriter;

#Stream
use uSAC::IO::SWriter;
use uSAC::IO::SReader;

use Socket  ":all";
#use IO::FD::DWIM ":all";
use IO::FD;

#use IO::Socket::IP '-register';



use Exporter;# qw<import>;


sub import {
	Socket->export_to_level(1, undef, ":all");

}

use Net::DNS::Native;

our $resolver=Net::DNS::Native->new(pool=>4, notify_on_begin=>1);

#asynchronous bind for tcp, udp, and unix sockets

use uSAC::IO::Common;
my $backend=uSAC::IO::Common::detect_backend;

my $rb=($backend."::IO");

die "Could not require $rb" unless(eval "require $rb");

#Create a socket with required family, type an protocol
#No bound or connected to anything
sub socket {
	my ($package, $fam, $type, $proto)=@_;
	my $socket;
	IO::FD::socket $socket,$fam, $type, $proto;
	$socket;
}

#Bind a socket to a host, port  or unix path. The host and port are strings
#Which are attmped to be converted to address structures applicable for the
#socket type Returns the address structure created Does not perform name
#resolving. you need to to know the address of the interface you wish to use
#A special case of localhost is resolved to the loopback devices appropriate to
#the family of the socket
#my ($package, $socket, $host, $port, $on_bind, $on_error)=@_;
sub bind{
	my $package=shift;
	my ($socket, $host, $port)=@_;

	my $fam= sockaddr_family IO::FD::getsockname $socket;

	die  "Not a socket" unless defined $fam;

	my $type=unpack "I", IO::FD::getsockopt $socket, SOL_SOCKET, SO_TYPE;

	say "Family is $fam, type is $type";
	say AF_INET;
	say SOCK_DGRAM;
	my $addr;

	if($fam==AF_INET or $fam==AF_INET6){
		my @addresses;
		my $error;
		my $flags=AI_PASSIVE;
		$flags|=AI_NUMERICHOST if$host eq "localhost";
			#Convert to address structures. DO NOT do a name lookup
		($error, @addresses)=getaddrinfo(
			$host,
			$port,
			{
				flags=>$flags,
				family=>$fam,
				type=>$type
			}
		);

		die $error if $error;

		my ($target)= grep {
			$_->{family} == $fam	#Matches INET or INET6
			#and $_->{socktype} == $type #Stream/dgram
			} @addresses;
		$addr=$target->{addr};
	}
	elsif($fam==AF_UNIX){
		$addr=pack_sockaddr_un $host;
	}
	else {
		die "Unsupported socket address family";
	}
	IO::FD::bind($socket, $addr) and $addr;
}

sub connect{
	my $package=shift;
	my ($socket, $host, $port, $on_connect, $on_error)=@_;
	#my @stat=stat $_[0];
	my $fam= sockaddr_family IO::FD::getsockname $socket;

	die  "Not a socket" unless defined $fam;

	my $type=unpack "I", IO::FD::getsockopt $socket, SOL_SOCKET, SO_TYPE;

	my $error;
	my @addresses;
	my $addr;

	if($fam==AF_INET or $fam==AF_INET6){
		#Convert to address structures. DO NOT do a name lookup
		($error, @addresses)=getaddrinfo(
			$host,
			$port,
			{
				flags=>AI_NUMERICHOST,
				family=>$fam,
				socktype=>$type
			}
		);
		$addr=$addresses[0]->{addr};
		
	}
	elsif($fam==AF_UNIX){
		$addr=pack_sockaddr_un $host;
	}
	else {
		die "Unsupported socket address family";
	}
	(ref($package)|| $rb)->connect($socket, $addr, $on_connect, $on_error);
}


sub cancel_connect {
	my $package=shift;
	(ref($package)||$rb)->cancel_connect(@_);
}

#Resolve a hostname to an address, then connect to it
sub resolve_connect{
	Net::DNS->resolve;
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

#Helper function for servers

sub to_address {

}
sub list_ipv4_interfaces {

	shift;
	my ($err, @list)=getaddrinfo(shift,undef,{
			#flags=>AI_CANONNAME,
		family=>AF_INET6,
	});

}

sub list_ipv6_interfaces {

}





sub writer {
	my $package=shift;

	my @stat=stat $_[0];
	if(-p $_[0]){
		return $package->swriter(@_);		
	}
	elsif(-S $_[0]){
		for(unpack "I", IO::FD::getsockopt $_[0], SOL_SOCKET, SO_TYPE){
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

		for(unpack "I", IO::FD::getsockopt $_[0], SOL_SOCKET, SO_TYPE){
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
