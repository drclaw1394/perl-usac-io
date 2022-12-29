package uSAC::IO::Sys::SSL;
use strict;
use warnings;
use feature qw<say state refaliasing>;

use IO::FD;
use Net::SSLeay;



#Generates wrappers to do read and write operations with perl filehandles via SSL
#Streams only

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

sub make_sysread {
  my $ssl=shift;      #The ssl object which does socket io
  my $listen_mode=shift;     #Client or server

  my $state=STATE_NEW;#Start state
  my $fd=-1;
  
  #Arguments to sub are same as sysread:
  #   $fd,  $buffer, $length, $offset
  sub {
    my $new_fd=$_[0];
    #Check what state the ssl needs to be in
    if($new_fd != $fd){

        if(ref($new_fd)){
          $fd=fileno($new_fd);
          $state=STATE_NEW;
        }
        else {
          $fd=$new_fd;
        }
    }
    
    \my $buffer=\$_[1];
    my $length=$_[2];
    
    my $res;
    my $trace=2;
    #Implement state machine here
    while(){
      if($state==STATE_NEW){
        if($listen_mode){
          #server listen
          Net::SSLeay::set_fd($ssl, $fd);
          say "FD for ssl is $fd";
          $state=STATE_ACCEPT;
          redo;
        }
        else{
          #Client connection
          die "Not implemented yet";
        }
      }
      elsif($state==STATE_ACCEPT){
        $res=Net::SSLeay::accept($ssl);
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
            #IO::FD::close $fd;
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
          #$r=undef;
          #IO::FD::close $fd;
          last;
        }
      }
      elsif($state==STATE_IO){
        say "STATE IO: Read";
        ($buffer, $res)=Net::SSLeay::read $ssl;#, $length;
        if($res>0){
            #byte count
            #say "REs is $res";
            say "Data read: $buffer";
            return $res;
            last;
        }
        else {
          #some sort of error
          say "ERROR IS $res";
          if($res==SSL_ERROR_WANT_READ){
            #sleep 1; 
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
      elsif($state==STATE_IDLE){
      }
      else {
      }
    }
  }
}


sub make_syswrite {
  my $ssl=shift;
  my $listen_mode=shift;
  my $state=STATE_NEW;
  my $fd=-1;
  sub {
    my $new_fd=$_[0];
    #Check what state the ssl needs to be in
    if($new_fd != $fd){

        if(ref($new_fd)){
          $fd=fileno($new_fd);
          $state=STATE_NEW;
        }
        else {
          $fd=$new_fd;
        }
    }
    my $fd=$_[0];
    \my $buffer=\$_[1];
    my $length=$_[2];

    my $res;
    my $trace=2;

    while(){
      if($state==STATE_NEW){
        if($listen_mode){
          #setup should be down by openssl
          $state=STATE_IO;
          redo;
        }
      }
      elsif($state=STATE_IO){
        say "STATE IO: write";
        $res=Net::SSLeay::write $ssl, $buffer;#, $length;
        if($res>0){
          #Success?
          return $res;
        }
        else {
          #some sort of error
          say "Write ERROR IS $res";
          if($res==SSL_ERROR_WANT_WRITE){
            #sleep 1; 
            say "->Want write... waiting for event";
            last;
          }
          elsif($res==SSL_ERROR_NONE){
            say "write NO ERROR";
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
  }
}
1;
