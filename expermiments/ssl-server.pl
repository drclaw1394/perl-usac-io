use v5.36;

use AnyEvent;
use Socket qw<:all>;
use IO::FD;
use Fcntl qw<O_NONBLOCK F_SETFL>;
use Net::SSLeay;


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

use enum qw<STATE_NEW STATE_ACCEPT STATE_IO STATE_IDLE>;
use constant {
  SSL_ERROR_NONE=>0,
  SSL_ERROR_SSL=>1,
  SSL_ERROR_WANT_READ=>2,
  SSL_ERROR_WANT_WRITE=>3,
  SSL_ERROR_WANT_X509_LOOKUP=>4,
  SSL_ERROR_SYSCALL=>5,
  SSL_ERROR_ZERO_RETURN=>6,
  SSL_ERROR_WANT_CONNECT=>7,
  SSL_ERROR_WANT_ACCEPT=>8
};
sub setup_client_ssl{
  #simply do an echo
  my $fd=$_[0];
  my $buffer="";
  my $state=STATE_NEW;
  my $ssl;
  my $r; $r=AE::io $_[0], 0, sub {
    my $run=1;
    while($run){
      if($state==STATE_NEW){
        say "STATE NEW";
        #setup connection
        print "sslecho: Creating SSL session (cxt=`$ctx')...\n" if $trace>1;
        $ssl = Net::SSLeay::new($ctx);
        $ssl or die_now("ssl new ($ssl): $!");

        print "sslecho: Setting fd (ctx $ctx, con $ssl)...\n" if $trace>1;
        Net::SSLeay::set_fd($ssl, $fd);
        $state=STATE_ACCEPT;
        redo;

      }
      elsif($state==STATE_ACCEPT){
        say "STATE ACCEPT";
        print "sslecho: Entering SSL negotiation phase...\n" if $trace>1;

        my $res=Net::SSLeay::accept($ssl);
        if($res<0){
          #Check the if want read or want write is set 
          $res=Net::SSLeay::get_error($ssl, $res);
          say "ERROR IS $res";
          if($res==SSL_ERROR_WANT_READ){
            sleep 1; 
            say "->Want read... waiting for event";
            last;
          }
          elsif($res==SSL_ERROR_SSL){
            say "ERROR IN SSL ON ACCEPT";
            #Close the connection
            IO::FD::close $fd;
            $r=undef;
            #$ssl=undef;
            last;
          }
          else {
            say "some other error";
          }
        }
        elsif($res==1){
          say "-> Successful accept";
          #successfuly accept
          print "sslecho: Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n" if $trace;
          $state=STATE_IO;
          redo;
        }
        else {
          #0. 
          #
          #Ssl failed
          say "->SSL failed. Shuting down";
          $r=undef;
          IO::FD::close $fd;
          last;
        }
      } 
      elsif($state==STATE_IO){
        say "STATE IO";
        my ($data,$res)=Net::SSLeay::read $ssl;
        if($res){
            #byte count
            say "Data read: $data";
            last;
        }
        else {
          #some sort of error
          say "ERROR IS $res";
          if($res==SSL_ERROR_WANT_READ){
            sleep 1; 
            say "->Want read... waiting for event";
            last;
          }
          elsif($res==SSL_ERROR_NONE){
            say "NO ERROR";
            sleep 5;
          }
          else {
            say "some other error";
            last;
          }

        }
      }
      else{
      }

    }
  };

  $client_table{$_[0]}=[$_[0],$_[1], $r];
}
