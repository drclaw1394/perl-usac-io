#!/usr/bin/env usac --backend AnyEvent
use strict;
use warnings;
no warnings "experimental";
use feature ":all";
use Data::Dumper;


use Test::More;


use uSAC::IO;		

use Socket ":all";

sub decode_DNS;

my $port=5353;#5050;
my $host="224.0.0.251";

#$host="ff02::fb";

my @list;
sub on_spec {
  say STDERR "ONSPEC";
  #Create a nonblocking socket
  my $fh;
  socket($fh, AF_INET, SOCK_DGRAM, 0) or die "Error making socket";

  #set socket options
  unless(setsockopt $fh, SOL_SOCKET, SO_REUSEADDR, 1){
    say STDERR "ERROR SETTING membership SOCKET OPTIONS";
    say STDERR $!;
  }

  unless(setsockopt $fh, SOL_SOCKET, SO_REUSEPORT, 1){
    say STDERR "ERROR SETTING membership SOCKET OPTIONS";
    say STDERR $!;
  }

  push @list, $fh; # retain the sockets

  #shift @_;
  #unshift @_, $fh;
  
  uSAC::IO::bind $fh, $_[1];
}

sub post_bind {
  say STDERR "POST BIND";
  #my (undef, $addr)=@_;
    my ($sock, $spec)=@_;
    say STDERR fileno $sock;
    my $addr=$spec->{addr};

  my $multicast=inet_aton "224.0.0.251";

  my $m=pack_ip_mreq $multicast, INADDR_ANY;

  unless(setsockopt $sock, IPPROTO_IP, IP_ADD_MEMBERSHIP , $m){
    say STDERR "ERROR SETTING membershipSOCKET OPTIONS";
    say STDERR $!;
  }

  say STDERR "My filehandle is: ".fileno $sock;
  #say "Other is  ". fileno $fh;
  my $reader=uSAC::IO::reader($sock);
  my $writer=uSAC::IO::writer(\*STDOUT);

  $reader->on_read=\&decode_DNS;
  $reader->start;


my $sender;
  #Create a nonblocking socket
  unless(socket($sender, AF_INET, SOCK_DGRAM, 0)){
    die "Error making sending socket";
  }

  my $id;
  my %spec=%$spec; #Copy
  $spec{data}{on_connect}= sub {
          say STDERR "CONNECT CALLBACK : $_[0]";
          my $output=uSAC::IO::dwriter(fh=>$_[0]);
          say STDERR $output;
          my $query=Net::DNS::Packet->new("rmbp.local", "A", "IN")->encode;
          #my $query=Net::DNS::Packet->new("google.com")->encode;
          #say STDERR unpack "H*", $query;
          $output->write($query, sub {say STDERR "Done"; uSAC::IO::connect_cancel $id; $id=undef;});
        };
  say STDERR "Sneder is ".fileno $sender;

  $id=uSAC::IO::connect( $sender, \%spec);
  ###############################################################################################
  #   {                                                                                         #
  #     address=>"224.0.0.251",                                                                 #
  #     port=>5353,                                                                             #
  #     data=>{                                                                                 #
  #       on_connect=>sub {                                                                     #
  #         say "CONNECT CALLBACK : $_[0]";                                                     #
  #         my $output=uSAC::IO::dwriter(fh=>$_[0]);                                            #
  #         say $output;                                                                        #
  #         my $query=Net::DNS::Packet->new("rmbp.local", "A", "IN")->encode;                   #
  #         #my $query=Net::DNS::Packet->new("google.com")->encode;                             #
  #         say unpack "H*", $query;                                                            #
  #         $output->write($query, sub {say "Done"; uSAC::IO::connect_cancel $id; $id=undef;}); #
  #       },                                                                                    #
  #       on_error=>sub {                                                                       #
  #         say "error"                                                                         #
  #       }                                                                                     #
  #   },                                                                                        #
  # }                                                                                           #
  ###############################################################################################
#);

  #my $t;$t=AE::timer 5, 0, sub {
  my $t;$t=uSAC::IO::timer 5, 0, sub {
    if(defined $id){
      uSAC::IO::connect_cancel($id);
      undef $t;
    }
  };
}


my $addr;
my $hints={
  address=>$host,
  port=>$port,
  socktype=>SOCK_DGRAM, protocol=>IPPROTO_UDP, flags=>0,

  data=>{
    on_error=>sub { say STDERR "ERROR HANDLER", "@_"},
    on_bind=>\&post_bind,
    on_spec=>\&on_spec
  }
};

#my ($sock,$addr)=@_;
#Socket bound
#my $multicast=pack_sockaddr_in 5050, 
#

say STDERR "Calling stage";
uSAC::IO::socket_stage( $hints, undef);#, \&uSAC::IO::bind);

say STDERR "AFTER Calling stage";


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

my %rev_type=reverse %type;
my %rev_qtype=reverse %qtype;

my %rev_class=reverse %class;
my %rev_qclass=reverse %qclass;

my @rr_decoders;
for my ($k,$v)(
  DNS_RR_TYPE_A, \&decode_A_rr,
  DNS_RR_TYPE_NS, \&decode_NS_rr,
  DNS_RR_TYPE_MD,\&decode_MD_rr,
  DNS_RR_TYPE_CNAME,\&decode_CNAME_rr,
  DNS_RR_TYPE_SOA,\&decode_SOA_rr,
  DNS_RR_TYPE_MB,\&decode_MB_rr,
  DNS_RR_TYPE_MG,\&decode_MG_rr,

  DNS_RR_TYPE_MR,\&decode_MR_rr,
  DNS_RR_TYPE_NULL,\&decode_NULL_rr,
  DNS_RR_TYPE_WKS,\&decode_WKS_rr,
  DNS_RR_TYPE_PTR,\&decode_PTR_rr,
  DNS_RR_TYPE_HINFO,\&decode_HINFO_rr,
  DNS_RR_TYPE_MINFO,\&decode_MINFO_rr,
  DNS_RR_TYPE_MX,\&decode_MX_rr,
  DNS_RR_TYPE_TXT,\&decode_TXT_rr,
  DNS_RR_TYPE_AAAA,\&decode_AAAA_rr,
){
  $rr_decoders[$k]=$v;
}

sub decode_DNS {
  #say STDERR "PARSE: ".unpack "H*", $_[0];
  use Net::DNS::Packet;
	say STDERR "";
	say STDERR "";

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
	say STDERR "ID: ".$id;
	say STDERR "Details: Query: $query, op_code: $op_code, aa: $aa, rd: $rd, ra: $ra, z: $z, rcode: $rcode";
	say STDERR "Q count: ".$qd_count;
	say STDERR "A count: ".$an_count;
	say STDERR "N count: ".$ns_count;
	say STDERR "R count: ".$ar_count;

  say STDERR "";
  my $prev;
  say STDERR "questions";
  for(1..$qd_count){
    #$prev=$total_offset;
    my $label=decode_name($_[0], $total_offset);
    my ($type, $class)=unpack "nn", substr $_[0], $total_offset, 4;
    $total_offset+=4;

    say STDERR  "Label: $label, type $type, class $class";
    say STDERR "";
    # 
  }
  say STDERR "";
  my $section=0;
  my @sections=qw<Answers Authorative Additional>;
  for my $count($an_count, $ns_count, $ar_count){
    say STDERR "Processing section: $sections[$section] at offset $total_offset (length ".length $_[0];
    for(1..$count){
      #$prev=$total_offset;
      my $label=decode_name($_[0], $total_offset);
      say STDERR "Total offset(after name): $total_offset";
      my ($type, $class, $ttl, $rd_len)=unpack "nnNn", substr $_[0], $total_offset, 10;# $total_offset;
      $total_offset+=10;

      say  STDERR "Label: $label, type $type, class $class, ttl $ttl, rd_len: $rd_len";
      say STDERR "REV TYPE: $rev_type{$type}";

      my $decoder=$rr_decoders[$type];
      if($decoder){
        my $res=$decoder->($_[0], $total_offset, $rd_len);
        #say length $res->[0];
        say STDERR Dumper [map unpack("H*", $_), @$res];#$res;
      }
      else {
        say STDERR "UNSUPPORTED TYPE:  $type ($rev_type{$type})";
        $total_offset+=$rd_len;
      }
      say STDERR "Total offset(after r data): $total_offset";
    }
    $section++;
  }
  $_[0]="";
}

# $_[0] is buffer
# $_[1] is offset
sub decode_name {
say STDERR "DECODE NAME";
say STDERR "========";

	my @stack=($_[1]);

	my $pos;
  my $pointer;
  my $label;
  my @labels;
  my $seen_ptr=0;

  while(@stack){
    $pos=pop @stack;
    say STDERR "";
  say STDERR "Offset: $pos";
  say STDERR "length ".length $_[0];
  #say "value: ".substr $_[0], $pos;


    my ($u, $l)=unpack "CC", substr $_[0], $pos;

    #say "TEST: ". unpack "H*", pack "C", 13;
    say STDERR "UPPER: ".unpack "H*",pack "C", $u;
    say STDERR "lower:".unpack "H*", pack "C", $l;
    if(0xC0 == ($u& 0xC0)) {
      $pointer= ($u& 0x3F)<<8;
      $pointer+=$l;

      $_[1]+=2 unless $seen_ptr;
      $seen_ptr=1;
      push @stack, $pointer;
    }
    elsif(0x40 ==($u&0xC0)){
        die "EXTENED DNS LABEL FOUND";

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
    $len+=length($s)+1;
    push @e, $s;
  }
  $_[1]+=$len;
  \@e;
}

sub decode_A_rr {
  my @e=unpack "a4", substr $_[0], $_[1];
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




sub decode_AAAA_rr {
  my @e=unpack "a16", substr $_[0], $_[1];
  $_[1]+=16;
  \@e;
}

#++

sub encode_HINFO_rr {
  \my $buf=$_[0]; shift;
  $buf.=pack "v/a* v/a*", $_[0]->@*;
}

