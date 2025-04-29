package uSAC::IO::Sys::SSL;
use strict;
use warnings;
use feature qw<state refaliasing>;

use IO::FD;
use POSIX qw<EAGAIN>;
use Net::SSLeay;



#Generates wrappers to do read and write operations with perl filehandles via SSL
#Streams only

use constant::more {
  STATE_NEW=>0,
  STATE_ACCEPT=>1,
  STATE_IO=>2,
  STATE_IDLE=>3
};

use constant::more {
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
          if($res==SSL_ERROR_WANT_READ){
            $res=undef;
            $!=EAGAIN;
            last;
          }
          elsif($res==SSL_ERROR_NONE){
            Log::OK::DEBUG and log_debug "ERROR NONE";
          }
          elsif($res==SSL_ERROR_SSL){
            Log::OK::DEBUG and log_debug "ERROR IN SSL ON ACCEPT";
            #Close the connection
            #IO::FD::close $fd;
            last;
          }
          else {
            Log::OK::DEBUG and log_debug "some other error";
          }
        }
        elsif($res==1){
          #successfuly accept
          print "sslecho: Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n" if $trace;
          $state=STATE_IO;
          redo;
        }
        else {
          #0. 
          #
          #Ssl failed
          Log::OK::DEBUG and log_debug "->SSL failed. Shuting down";


          #Force an error for the reader/writer
          $res=undef;
          $!=0;
          last;
        }
      }

      elsif($state==STATE_IO){
        ($buffer, $res)=Net::SSLeay::read $ssl;#, $length;
      
        last if $res>0;  #Read  was a success! Return byte count

        #some sort of error
        $res=Net::SSLeay::get_error($ssl, $res);
        if($res==SSL_ERROR_WANT_READ){
          #Emulate an EAGAIN error
          $res=undef;
           $!=EAGAIN;
          last;
        }
        elsif($res==SSL_ERROR_WANT_WRITE){
          #Emulate an EAGAIN error?
          #this would occur if a handshake was required
          Net::SSLeay::write($ssl, ""); #write no applicaiton data. just force SSL write
          $res=undef;
          $!=EAGAIN;
          last;
        }
        elsif($res==SSL_ERROR_ZERO_RETURN){
          Log::OK::DEBUG and log_debug "SSL_ERROR_ZERO_RETURN in sysread";
          Log::OK::DEBUG and log_debug "CLIENT CLOSED THE CONNECTION";
          $res=0; #Emulate EOF condition?
          last;
        }
        elsif($res==SSL_ERROR_NONE){
          Log::OK::DEBUG and log_debug "SSL_ERROR_NONE in sysread";
        }
        elsif($res==SSL_ERROR_SSL){
          Log::OK::DEBUG and log_debug "SSL_ERROR_SSL in sysread";
          $res=undef;
          $!=0; #TODO set approprate error
          last;
        }
        elsif($res==SSL_ERROR_WANT_X509_LOOKUP){
          Log::OK::DEBUG and log_debug "SSL_ERROR_WANT_X509_LOOKUP in sysread";
          last;
        }
        elsif($res== SSL_ERROR_SYSCALL){
          Log::OK::DEBUG and log_debug "SSL_ERROR_SYSCALL in sysread";
          last;
        }
        elsif($res== SSL_ERROR_WANT_CONNECT){
          Log::OK::DEBUG and log_debug "SSL_ERROR_WANT_CONNECT in sysread";
          last;
        }
        elsif($res== SSL_ERROR_WANT_ACCEPT){
          Log::OK::DEBUG and log_debug "SSL_ERROR_WANT_ACCEPT in sysread";
          last;
        }
        else {
          Log::OK::DEBUG and log_debug "some other ssl error in sysread";
          last;
        }
      }



      elsif($state==STATE_IDLE){
      }
      else {
      }
    }

    $res;
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
        $res=Net::SSLeay::write $ssl, $buffer;#, $length;
        if($res>0){
          #Success?
          return $res;
        }
        else {
          #some sort of error
          $res=Net::SSLeay::get_error($ssl, $res);
          if($res==SSL_ERROR_WANT_WRITE){
            #sleep 1; 
            Log::OK::DEBUG and log_debug "->Want write... waiting for event";
            last;
          }
          elsif($res==SSL_ERROR_WANT_READ){
            Net::SSLeay::read $ssl,0; #force a read by take no data
          }
          elsif($res==SSL_ERROR_NONE){
            Log::OK::DEBUG and log_debug STDERR "SSL_ERROR_NONE in syswrite";
          }
          elsif($res==SSL_ERROR_WANT_X509_LOOKUP){
            Log::OK::DEBUG and log_debug STDERR "SSL_ERROR_WANT_X509_LOOKUP in syswrite";
            last;
          }
          elsif($res== SSL_ERROR_SYSCALL){
            Log::OK::DEBUG and log_debug STDERR "SSL_ERROR_SYSCALL in syswrite";
            last;
          }
          elsif($res== SSL_ERROR_WANT_CONNECT){
            Log::OK::DEBUG and log_debug STDERR "SSL_ERROR_WANT_CONNECT in syswrite";
            last;
          }
          elsif($res== SSL_ERROR_WANT_ACCEPT){
            Log::OK::DEBUG and log_debug STDERR "SSL_ERROR_WANT_ACCEPT in syswrite";
            last;
          }
          elsif($res== SSL_ERROR_ZERO_RETURN){
            Log::OK::DEBUG and log_debug "SSL_ERROR_ZERO_RETURN in sysread";
            Log::OK::DEBUG and log_debug "CLIENT CLOSED THE CONNECTION";
            $res=undef;
            $!=0;
            last;
          }
          else {
            Log::OK::DEBUG and log_debug "some other ssl error in syswrite";
            last;
          }

        }

      }
      else{
      }
    }
    $res;
  }
}
1;
