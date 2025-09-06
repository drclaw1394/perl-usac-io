#!/usr/bin/env usac --backend AnyEvent

use uSAC::Log;
use Log::OK;
use uSAC::IO;
use IO::FD;
use Fcntl qw<O_NONBLOCK F_GETFL F_SETFL>;
use Socket::More::Constants;
use Data::Dumper;
use Socket::More;

use uSAC::IO::SReader;
use uSAC::IO::SWriter;





use Net::SSLeay;
use uSAC::IO::Sys::SSL;
my ($port, $cert_pem, $key_pem)=@ARGV;

$port//=8000;
$cert_pem//="cert.pem";
$key_pem//="key.pem";

asay $STDERR, "CONFIGURED FOR port $port, cert $cert_pem,  key $key_pem";
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








my @readers;
my @writers;

my $hints={
  socktype=>SOCK_STREAM,
  address=>"0.0.0.0",
  port=>9091,
  data=>{
    on_bind=>sub {
      asay $STDERR, "ON BIND";
      my $fh=$_[0];
      my $flags=IO::FD::fcntl $fh, F_GETFL, 0;
      die $! unless defined $flags;
      $flags|=O_NONBLOCK;

      defined IO::FD::fcntl $fh, F_SETFL, $flags or die "COULD NOT SET NON BLOCK on $fh: $!";
      
      &listen,
    },
    on_listen=>sub {
      asay $STDERR, "ON listen";
      &accept;
    },
    on_accept=>sub {
      asay $STDERR, "ACCEPTED CONNECTION, ". Dumper @_;
      for ($_[0]->@*){
        my $ssl;
        #print "sslecho: Creating SSL session (cxt=`$ctx')...\n";
        $ssl = Net::SSLeay::new($ctx);

        $ssl or die_now("ssl new ($ssl): $!");
        
        Net::SSLeay::set_rfd($ssl, $_);
        Net::SSLeay::set_wfd($ssl, $_);

        my ($sysread, $syswrite)=uSAC::IO::Sys::SSL::make_sysread_syswrite $ssl, 1;
        #my $syswrite=uSAC::IO::Sys::SSL::make_syswrite $ssl, 1;

        asay $STDERR, "sysread $sysread";
        asay $STDERR, "syswrite $syswrite";
        
        my $r=uSAC::IO::SReader::create(fh=>$_, sysread=>$sysread);
        asay $STDERR, "$r";
        #
        #my $r=sreader fh=>$_;
        $r->pipe_to($STDOUT);
        my $w=uSAC::IO::SWriter::create(fh=>$_, syswrite=>$syswrite);
        #my $w= swriter fh=>$_;
        asay $STDERR, "$w";
        push @readers, $r;
        push @writers, $w;
        $r->start;
      }

      asay $STDERR, "------at end\n";

    },

    on_connect=>sub {
      asay $STDERR, "CONNECTED @_";
    },

    on_error=>sub {
      asay $STDERR, @_;
      $STDERR->flush;
    },

    on_socket=>sub{
      asay $STDERR, Dumper @_;
      #
      #Allow address reuse
      my $fh=$_[0];

      IO::FD::setsockopt($fh, SOL_SOCKET, SO_REUSEADDR, pack "i", 1) or die $!;
      IO::FD::setsockopt $fh, SOL_SOCKET, SO_REUSEPORT, pack "i", 1 or die $!;
      &bind;
    }



  }
};

$STDIN->on_read=sub {
  print "STDIN ". Dumper @_;
  #my $buffer=$_[0][0];
  for(@writers){
    $_->write(@_);
  }
  $_[0][0]=""; # Consume input
};

timer 0, 5, sub {
  #print "Timer\n";
  for(@writers){
    #print "write to peer\n";
    $_->write([time."\n"]);
  }
};

$STDIN->start;

socket_stage  $hints;

1;
