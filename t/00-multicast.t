use strict;
use warnings;
use feature ":all";


use Time::HiRes qw<sleep>;
use Test::More;

use EV;
use AnyEvent;

use uSAC::IO;		

use Socket ":all";

my $cv=AE::cv;

my $port=5353;#5050;
my $host="224.0.0.251";
#$host="ff02::fb";

#Create a nonblocking socket
my $fh="asdf";;
unless($fh=uSAC::IO->socket(AF_INET, SOCK_DGRAM, 0)){
	die "Error making socket";
}

#set socket options
unless(setsockopt $fh, SOL_SOCKET, SO_REUSEPORT, 1){
	say "ERROR SETTING membership SOCKET OPTIONS";
	say $!;
}


sub parse_DNS;
#uSAC::IO->bind_inet(
my $addr;
unless($addr=uSAC::IO->bind($fh, $host, $port)){
	die "Could not bind";
}

#my ($sock,$addr)=@_;
#Socket bound
#my $multicast=pack_sockaddr_in 5050, 
#
my $multicast=inet_aton "224.0.0.251";
say $multicast;
say "ANY: ", unpack "H*", INADDR_ANY;
my $m=pack_ip_mreq $multicast, INADDR_ANY;
unless(setsockopt $fh, IPPROTO_IP, IP_ADD_MEMBERSHIP , $m){
	say "ERROR SETTING membershipSOCKET OPTIONS";
	say $!;
}

say "My filehandle is: $fh";
my $reader=uSAC::IO->reader(fh=>$fh);
my $writer=uSAC::IO->writer(fh=>\*STDOUT);

$reader->on_read=\&parse_DNS;
$reader->start;


#Create a nonblocking socket
my $sender;
unless($sender=uSAC::IO->socket(AF_INET, SOCK_DGRAM, 0)){
	die "Error making sending socket";
}

my $id=uSAC::IO->connect(
	$sender,
	"224.0.0.251",
	5353,
	sub {
		my $output=uSAC::IO->writer(fh=>$_[0]);
		my $query=Net::DNS::Packet->new("rmbp.local")->encode;
		#say unpack "H*", $query;
		$output->write($query,sub {say "Done"});
	}
	,sub {
		say "error"
	}
);

my $t;$t=AE::timer 5, 0, sub {
	try {
		die "connection id: $id";
	}
	catch ($e){
		say "Caught exception";
	}
	uSAC::IO->cancel_connect($id);
	undef $t;
};

$cv->recv;

#Header
#question
#answer
#authority
#additional

sub parse_DNS {
	################################################
	# use Data::Dumper;                            #
	use Net::DNS::Packet;
	my $packet=Net::DNS::Packet->decode(\$_[0]);
	$packet->print;

	return;
	################################################
	say "";
	say "";
	my $total_offset=0;
	my $org=$_[0];
	\my $buf=\$_[0];
	my ($id, $details, $qd_count, $an_count, $ns_count, $ar_count)=unpack "n*", substr $buf, 0,12,"";
	$total_offset+=12;
	my ($query, $op_code, $aa, $tc,$rd,$ra,$z, $rcode);
	$query=$details >> 15;
	$op_code=	(0b0111100000000000 & $details)>>11;
	$aa=		(0b0000010000000000 & $details)>>10;
	$tc=		(0b0000001000000000 & $details)>>9;
	$rd=		(0b0000000100000000 & $details)>>8;
	$ra=		(0b0000000010000000 & $details)>>7;
	$z= 		(0b0000000001110000 & $details)>>4;
	$rcode= 	(0b0000000000001111 & $details);
	#pack
	say "ID: ".$id;
	say "Details: Query: $query, op_code: $op_code, aa: $aa, rd: $rd, ra: $ra, z: $z, rcode: $rcode";
	say "Q count: ",$qd_count;
	say "A count: ",$an_count;
	say "N count: ",$ns_count;
	say "R count: ",$ar_count;




	my $counter=$qd_count;
	my $label;
	my $offset=0;
	my $compression;
	my $pointer;

	my @stack;
	my $overall=$total_offset;
	push @stack, $overall;
	my $pos;
	while($counter){
		my @labels;
		my $reset=1;
		say "Counter: $counter";
		while(@stack){
			$pos=pop @stack;

			#say "position: $pos";
			my $compression=unpack "n", substr $org, $pos;
			#say unpack "H*", pack "S", $compression;

			if(0xC000 == ($compression & 0xC000)) {

				$pointer= $compression & 0x3F;
				#	say "compression detected: pointer: $pointer";

				#update overall position if stack is empty
				$overall=$pos+2 if $reset;
				$reset=undef;


				push @stack, $pointer;
			}
			else {
				#con
				$label=unpack "C/a", substr $org, $pos;
				push @labels, $label;
				#say "Label: ".$label;
				$offset=1+length($label);

				push @stack, $pos+$offset if $label;
				$overall=$pos+$offset if $reset;#!$label and !$pointer;
			}
			#last unless $label;
		}
		my ($qtype,$qclass)=unpack "nn", substr $org, $overall;
		push @stack, $overall+4;
		say "Name: ".join ".", @labels;
		$counter--;
	}
}
