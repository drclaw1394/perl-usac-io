use v5.36;

use AnyEvent;
use Socket qw<:all>;
use IO::FD;
use Fcntl qw<O_NONBLOCK F_SETFL>;
use Net::SSLeay;
use uSAC::IO::Sys::SSL;


my $trace=2;

my ($port, $cert_pem, $key_pem)=@_;

$port//=8000;
$cert_pem//="cert.pem";
$key_pem//="key.pem";

#
# Prepare SSLeay
#

Net::SSLeay::load_error_strings();
Net::SSLeay::ERR_load_crypto_strings();
Net::SSLeay::SSLeay_add_ssl_algorithms();
Net::SSLeay::randomize();
my $ctx = Net::SSLeay::CTX_new ();
$ctx or die_now("CTX_new ($ctx): $!\n");
Net::SSLeay::CTX_set_cipher_list($ctx,'ALL');
Net::SSLeay::set_cert_and_key($ctx, $cert_pem, $key_pem) or die "key";



my %client_table;
#Create a listening socket
die "Could not create socket" unless defined IO::FD::socket my $socket, AF_INET, SOCK_STREAM, 0;

my ($error,@res);
($error,@res)=getaddrinfo("0.0.0.0",$port,{flags=>AI_NUMERICHOST|AI_PASSIVE, family=>AF_INET, type=>SOCK_STREAM});
my $addr=$res[0]{addr};
die "Error $error" if $error;

die "Failed to set non blocking" unless defined IO::FD::fcntl $socket, F_SETFL, O_NONBLOCK;
die "Could not set address reuse $!" unless defined  IO::FD::setsockopt $socket, SOL_SOCKET, SO_REUSEADDR, 1;
die "Could not bind $!" unless defined IO::FD::bind $socket, $addr;
die "Could not listen $!" unless defined IO::FD::listen $socket, 10;

my $cv=AE::cv;


my $lw; $lw=AE::io $socket, 0, sub {
  #when new sockets ready for accepting
  my @client;
  my @peer;
  my $count=IO::FD::accept_multiple @client, @peer, $socket;
  if(defined $count){
    for(0..$#client){
      #setup_client($client[$_],$peer[$_]);
        setup_client_ssl($client[$_],$peer[$_]);
    }
    @client=();
    @peer=();
  }
};

my $timer; $timer=AE::timer 0,1, sub {
  say "waiting";
};



$cv->recv;


sub setup_client{
  #simply do an echo
  my $fd=$_[0];
  my $buffer="";
  my $r; $r=AE::io $_[0], 0, sub {
    IO::FD::sysread $fd, $buffer, 4096;
    say $buffer;
  };

  $client_table{$_[0]}=[$_[0],$_[1], $r];
}

sub setup_client_ssl{
  #simply do an echo
  my $fd=$_[0];
  my $buffer="";
  my $ssl;
  print "sslecho: Creating SSL session (cxt=`$ctx')...\n" if $trace>1;
  $ssl = Net::SSLeay::new($ctx);
  $ssl or die_now("ssl new ($ssl): $!");
  my $sysread=uSAC::IO::Sys::SSL::make_sysread $ssl, 1;
  my $syswrite=uSAC::IO::Sys::SSL::make_syswrite $ssl, 1;
  my $r; $r=AE::io $_[0], 0, sub {
      $sysread->($fd,\$buffer,4096);
      say $buffer;
  };
  $client_table{$_[0]}=[$_[0],$_[1], $r];
}
