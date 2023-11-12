use strict;
use warnings;
use feature ":all";


use Time::HiRes qw<sleep>;
use Test::More;

use EV;
use AnyEvent;

use uSAC::IO;		

use Socket ":all";

sub parse_DNS;
my $cv=AE::cv;

my $port=5353;#5050;
my $host="224.0.0.251";

#$host="ff02::fb";

#Create a nonblocking socket
socket(my $fh, AF_INET, SOCK_DGRAM, 0) or die "Error making socket";

#set socket options
unless(setsockopt $fh, SOL_SOCKET, SO_REUSEADDR, 1){
        say "ERROR SETTING membership SOCKET OPTIONS";
        say $!;
}
unless(setsockopt $fh, SOL_SOCKET, SO_REUSEPORT, 1){
        say "ERROR SETTING membership SOCKET OPTIONS";
        say $!;
}


my $addr;
uSAC::IO::bind($fh, $host, $port,
  \&post_bind,
  sub {
        die "Could not bind";
  }
);

#my ($sock,$addr)=@_;
#Socket bound
#my $multicast=pack_sockaddr_in 5050, 
#
my $sender;
sub post_bind {
    my (undef, $addr)=@_;
    say "POST BIND: ".$addr;
  my $multicast=inet_aton "224.0.0.251";
  say $multicast;
  say "ANY: ", unpack "H*", INADDR_ANY;
  my $m=pack_ip_mreq $multicast, INADDR_ANY;
  unless(setsockopt $fh, IPPROTO_IP, IP_ADD_MEMBERSHIP , $m){
    say "ERROR SETTING membershipSOCKET OPTIONS";
    say $!;
  }

  say "My filehandle is: $fh";
  my $reader=uSAC::IO::reader(fh=>$fh);
  my $writer=uSAC::IO::writer(fh=>\*STDOUT);

  $reader->on_read=\&parse_DNS;
  $reader->start;


  #Create a nonblocking socket
  unless(socket($sender, AF_INET, SOCK_DGRAM, 0)){
    die "Error making sending socket";
  }

  say "Sneder is ".fileno $sender;
  my $id=uSAC::IO::connect(
    $sender,
    "224.0.0.251",
    5353,
    sub {
      say "CONNECT CALLBACK : $_[0]";
      my $output=uSAC::IO::dwriter(fh=>$_[0]);
      say $output;
      my $query=Net::DNS::Packet->new("rmbp.local", "A", "IN")->encode;
      #my $query=Net::DNS::Packet->new("google.com")->encode;
      #say unpack "H*", $query;
      $output->write($query, sub {say "Done"});
      #
      #my $res=send $sender, $query, 0;
      #say "RES is $res";
      
      #my $res =IO::FD::send $_[0], $query, 0;
      #say "RES is $res";
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
    uSAC::IO::connect_cancel($id);
    undef $t;
  };
}

$cv->recv;

#Header
#question
#answer
#authority
#additional

#https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml#dns-parameters-2
my $i=1;
my %type=((map { ($_,$i++)} qw<A NS MD MF CNAME SOA MB MG MR NULL WKS PTR HINFO MINFO MX TXT>),AAAA=>28);

my $rev_type=reverse %type;

my %qtype=(%type, AFXR=>252, MAILB=>253, MAILA=>254, "*"=>255);
my %rev_qtype=reverse %qtype;

$i=1;
my %class=map { ($_,$i++)} qw<IN CS CH HS>;
my $rev_class=reverse %class;

my %qclass=(%class, "*"=>255);
my %rev_qclass=reverse %qclass;


sub parse_DNS {
	################################################
	# use Data::Dumper;                            #
  use Net::DNS::Packet;
  #my $packet=Net::DNS::Packet->decode(\$_[0]);
  #$packet->print;
  #
  #return;
	################################################
	say "";
	say "";
	my $total_offset=0;
	\my $buf=\$_[0];
	my ($id, $details, $qd_count, $an_count, $ns_count, $ar_count)=unpack "n*", substr $buf, 0,12;
	$total_offset=12;
  
  open my $out, ">", "out.dat";
  print $out  $buf;
  close $out;

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

  say "";
  say "questions";
  for(1..$qd_count){
    my $label=decode_name(\$_[0], \$total_offset);
    my ($type, $class)=unpack "nn", substr $buf, $total_offset;
    $total_offset+=4;
    say  "Label: $label, type $type, class $class";
    say"";
  }
  say "";
  say "Answers:";
  for(1..$an_count){
    my $label=decode_name(\$_[0], \$total_offset);
    my ($type, $class, $ttl, $rd_len)=unpack "nnNn", substr $buf, $total_offset;
    say  "Label: $label, type $type, class $class, ttl $ttl, rd_len: $rd_len";

    $total_offset+=10;
    my $rdata=substr $buf,$total_offset, $rd_len;
    $total_offset+=$rd_len;
  }
  $_[0]="";
}

sub decode_name {
say "DECODE NAME";
  \my $buf=$_[0];
	\my $overall=$_[1];

	my @stack=($overall);

	my $pos;
  my $pointer;
  my $label;
  my @labels;
  my $seen_ptr=0;

  while(@stack){
    $pos=pop @stack;

    my ($u, $l)=unpack "CC", substr $buf, $pos;

    if(0xC0 == ($u& 0xC0)) {
      $pointer= ($u& 0x3F)<<8;
      $pointer+=$l;

      $overall+=2 unless $seen_ptr;
      $seen_ptr=1;
      push @stack, $pointer;
    }
    elsif($u) {
      #con
      $pos++;
      $label=unpack "a*", substr $buf, $pos, $u;
      push @labels, $label;
      $pos+=$u;
      $overall+=($u+1) unless $seen_ptr;
      push @stack, $pos;
    }
    else {
      #empty label
      $overall++ unless $seen_ptr;
    }
    #last unless $label;
  }

  join ".", @labels;
}
