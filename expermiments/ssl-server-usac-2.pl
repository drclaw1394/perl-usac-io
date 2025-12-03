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


Net::SSLeay::CTX_set_tlsext_servername_callback($ctx, sub {
    my $ssl = shift;
    my $h = Net::SSLeay::get_servername($ssl);
    asay $STDERR, "---SERVER NAME INDICATED is $h";
    #my $rv=Net::SSLeay::P_alpn_selected($ssl);
    #Net::SSLeay::set_SSL_CTX($ssl, $hostnames{$h}->{ctx}) if exists $hostnames{$h};
} );


Net::SSLeay::CTX_set_alpn_select_cb($ctx, ['http/1.1']);







my @readers;
my @writers;

#  Cert Staging List
#   A list of cert and key pairs. Adding to the list only if pair doesn't exist only
#   after staging the certs are loaded and added to the secrets table
#   the certs have the subject alternative name matchers added to the secrets table,
#     this handles the wild card matching
# 
#  Secrets table (a hustle table)
#   matchers are hostnames, values are is an array with cert, key, and openssl conext
#   
# 
#  NEW ACCEPTED CONNECTION ALGORITHM 
#  ----------------------------------
#
#  Add the listening fd to fd table (fd=>spec)
#  on accept do a look up in the table with listening fd to get spec
#  from spec extract the hostnames array and protocols array
#
#  save list of hostnames from spec in to session (for protocol specifiy matching)
#
#  create reader and writer with default openssl context
#  save default ssl context in pre-session
#
#  if SNI is used
#   check the hostname exists in session saved hostname list
#    if found
#       lookup secrets with found hostname
#       save the ctx for hostname in pre-session (overwrite default)
#       create enw reader and writer for  with new ctx
#
#    else drop connection
#      end
#
#
#  else SNI not used
#     default ctx is already sabed
#     save reader and writer  already createed
#
#
# ALPN callback
#    check protocols list saved previously
#     if found  use protocol name in protocol table
#     save /create parser/serialiser in pre-session
#
#
# Create session with reader/wrier/ hostname, parser

my $hints={
  socktype=>SOCK_STREAM,
  address=>"0.0.0.0",
  port=>$port,
  data=>{
    keys=>[],         # paths to load
    certs=>[],        # paths to load
    hostnames=>[],    # hostnames to mach SNI
    protocols=>[],    # ALPN protocols to select from

    on_server_name=> sub {

    },

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
      asay $STDERR, "ACCEPTED CONNECTION, ". Dumper $_[1];
      for ($_[0]->@*){
        my ($sysread, $syswrite, $ssl)=uSAC::IO::Sys::SSL::make_sysread_syswrite $ctx, $_, $_, 1;

        asay $STDERR, "sysread $sysread";
        asay $STDERR, "syswrite $syswrite";
        
        my $r=uSAC::IO::SReader::create(fh=>$_, sysread=>$sysread);
        $r->pipe_to($STDOUT);
        my $w=uSAC::IO::SWriter::create(fh=>$_, syswrite=>$syswrite);

        push @readers, $r;
        push @writers, $w;

        asay $STDERR, "---ABOUT TO START READER--";
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
