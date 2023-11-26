use strict;
use warnings;
use feature ":all";


use Time::HiRes qw<sleep>;
use Test::More;

use EV;
use AnyEvent;

use uSAC::IO;		

use Socket ":all";

sub decode_DNS;
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

  $reader->on_read=\&decode_DNS;
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
my %type;
my %qtype;
my %class;
my %qclass;
my $i;
BEGIN{
  my $i=1;
  %type=((map { ($_, $i++)} qw<A NS MD MF CNAME SOA MB MG MR NULL WKS PTR HINFO MINFO MX TXT>),AAAA=>28);
  %qtype=(%type, AFXR=>252, MAILB=>253, MAILA=>254, "*"=>255);

  $i=1;
  %class=map { ($_,$i++)} qw<IN CS CH HS>;
  %qclass=(%class, "*"=>255);


}
use constant::more map { ("DNS_RR_TYPE_$_", $type{$_})} keys %type;
use constant::more map { ("DNS_Q_TYPE_$_", $type{$_})} keys %qtype;

use constant::more map { ("DNS_RR_CLASS_$_", $class{$_})} keys %class;
use constant::more map { ("DNS_Q_TYPE_$_", $qclass{$_})} keys %qclass;

my $rev_type=reverse %type;
my %rev_qtype=reverse %qtype;

my $rev_class=reverse %class;
my %rev_qclass=reverse %qclass;

my @rr_decoders;
$rr_decoders[DNS_RR_TYPE_A]=\&decode_A_rr;
$rr_decoders[DNS_RR_TYPE_CNAME]=\&decode_CNAME_rr;

sub decode_DNS {
  say "PARSE: ".unpack "H*", $_[0];
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
  #my $org_message=$_[0]; # Copy for name decoding
  my $total_offset=0;    # Reset offset

	my ($id, $details, $qd_count, $an_count, $ns_count, $ar_count)=unpack "n6", substr $_[0], $total_offset, 12;
  $total_offset+=12;
  
  #open my $out, ">", "out.dat";
  #print $out  $buf;
  #close $out;

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
  my $prev;
  say "questions";
  for(1..$qd_count){
    #$prev=$total_offset;
    my $label=decode_name($_[0], $total_offset);
    my ($type, $class)=unpack "nn", substr $_[0], $total_offset, 4;
    $total_offset+=4;

    say  "Label: $label, type $type, class $class";
    say"";
    # 
  }
  say "";
  say "Answers:";
  for(1..$an_count){
    #$prev=$total_offset;
    my $label=decode_name($_[0], $total_offset);
    #substr $_[0], 0, $total_offset-$prev, "";
    say "Total offset: $total_offset";
    my ($type, $class, $ttl, $rd_len)=unpack "nnNn", substr $_[0], $total_offset, 10;# $total_offset;
    say  "Label: $label, type $type, class $class, ttl $ttl, rd_len: $rd_len";
    $total_offset+=10;
    my $rdata=substr $_[0], 0, $rd_len; #$total_offset, $rd_lenr
    $total_offset+=$rd_len;

    #Lookup type in


  }
  $_[0]="";
}

# $_[0] is buffer
# $_[1] is offset
sub decode_name {
say "DECODE NAME";

  my $prev= $_[1];
	my @stack=($_[1]);

	my $pos;
  my $pointer;
  my $label;
  my @labels;
  my $seen_ptr=0;

  while(@stack){
    $pos=pop @stack;

    my ($u, $l)=unpack "CC", substr $_[0], $pos;

    if(0xC0 == ($u& 0xC0)) {
      $pointer= ($u& 0x3F)<<8;
      $pointer+=$l;

      $_[1]+=2 unless $seen_ptr;
      $seen_ptr=1;
      push @stack, $pointer;
    }
    elsif($u) {
      #con
      $pos++;
      $label=unpack "a*", substr $_[0], $pos, $u;
      push @labels, $label;
      $pos+=$u;
      $_[1]+=($u+1) unless $seen_ptr;
      push @stack, $pos;
    }
    else {
      #empty label
      $_[1]++ unless $seen_ptr;
    }
    #last unless $label;
  }
  #substr $_[0], 0, $_[2]-$prev, "";

  join ".", @labels;

}

sub decode_rr {
  
}


# supports compression. first argument is original buffer, second buffer is offset
sub _decode_name { [&decode_name]}
*decode_CNAME_rr=\*_decode_name;
*decode_MB_rr=\*_decode_name;
*decode_MF_rr=\*_decode_name;
*decode_MG_rr=\*_decode_name;

sub decode_MINFO_rr {
  my @e=(&decode_name, &decode_name);
  return undef unless @e==2;
  \@e;
}

*decode_MR_rr=\*_decode_name;

sub decode_MX_rr {
  my @e=unpack "v", substr $_[0], $_[1], 2;
  $_[1]+=2;
  push @e, &decode_name;
  \@e;
}

# buf, offset, rdata_len
sub decode_NULL_rr {
  my @e=substr $_[0], $_[1], $_[2];
  $_[1]+=$_[2];
  \@e;
  
}

*decode_NS_rr=\*_decode_name;
*decode_PTR_rr=\*_decode_name;

sub decode_SOA_rr {
  my @e=( &decode_name &decode_name);
  push @e, unpack "V5", substr $_[0], $_[0];
  $_[1]+=20;
  \@e;
}

sub decode_TXT_rr {
  my @e;
  my $len=0;
  my $s;
  while($len<$_[2]){
    $s=unpack "C/a*", substr $_[0], $_[1]+$len;
    $len+=length $s;
    push @e, $s;
  }
  $_[1]+=$len;
  \@e;
}

sub decode_A_rr {
  my @e=unpack "V", substr $_[0], $_[1];
  $_[1]+=4;
  \@e;
}

sub decode_WKS_rr {
  my @e=unpack "VC", substr $_[0], $_[1];
  $_[1]+=5;
  push @e, substr $_[0], $_[1],$_[2]-5;
  $_[1]+=$_[2]-5;
  \@e;
}

sub decode_HINFO_rr {
  my @hc=unpack  "C/a* C/a*", substr $_[0], $_[1];
  return undef unless @hc==2;
  my $len=length($hc[0])+length($hc[1])+2;
  $_[1]+=$len; 
  #substr $_[0], 0, $len, "";
  \@hc;
}


#++

sub encode_HINFO_rr {
  \my $buf=$_[0]; shift;
  $buf.=pack "v/a* v/a*", $_[0]->@*;
}


