package uSAC::IO::Sys::SSL;
use strict;
use warnings;
use feature qw<state refaliasing>;
use Log::OK;
use uSAC::Log;

use uSAC::IO;

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

# Create replacement sysread and syswrite functions. 
# NOTES on sysread:
# NOTE: IMPORTANT 
#   Sysread does not use the fd supplied (as this is set in the ssl object
#   sysread does not use respect the length field. THe data from ssl will be used as it is returned
#   sysred offset is respected and data is append to that point in the buffer
#
#   syswrite does not use the fd supplied (as above)
#   


sub make_sysread_syswrite {
  my $ssl=shift;            #The ssl object which does socket io
  my $listen_mode=shift;    #Client or server
  my $state=STATE_NEW;      #Start state

    #Arguments to sub are same as sysread:
    #   $fd,  $buffer, $length, $offset
    my $sysread= sub {
      #asay $STDERR, "__ TOP OF SYSREAD";
      #my $fd=$_[0]; 
      \my $buffer=\$_[1];
      my $length=$_[2];
      my $offset=$_[3];

      my $res;
      my $trace=2;
      #Implement state machine here
      while(){
        #asay $STDERR, "in reader while";
        if($state==STATE_NEW){
          if($listen_mode){
            #server listen
            #Net::SSLeay::set_fd($ssl, $rfd);
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
              Log::OK::DEBUG and log_debug "some other error: $res";
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
          my $buf;

          # NOTE:
          # A temp buffer is used to then append to a sysread buffer. Otherwise
          # the existing contents of sysread buffer get destroyed (ie does not
          # append)
          #
          #TODO: possibly use bio read with a max value as a better fit?
          #
          ($buf, $res)=Net::SSLeay::read $ssl;
          substr($buffer, $offset) = $buf;   #Append at offset

          #asay $STDERR, "ssl read return buffer $buffer, and res $res";
          last if $res>0;  #Read  was a success! Return byte count

          #some sort of error
          $res=Net::SSLeay::get_error($ssl, $res);
          if($res==SSL_ERROR_WANT_READ){
            #asay $STDERR, " sysread needs EAGAIN";
            #Emulate an EAGAIN error
            $res=undef;
            $!=EAGAIN;
            last;
          }
          elsif($res==SSL_ERROR_WANT_WRITE){
            #asay $STDERR, " sysread needs write";
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
            $res=undef;
            #$!=0;
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
      #asay $STDERR, "----END OF SYSREAD\n";
      $res;
    };


    my $syswrite=sub {
      #my $fd=$_[0];
      \my $buffer=\$_[1];
      my $offset=$_[3]//0;

      my $length=$_[2]//(length($buffer)-$offset);

      my $res;
      my $trace=2;

      while(){
        #asay($STDERR, "in writer while $state");
        if($state==STATE_NEW){
          if($listen_mode){
            #setup should be down by openssl
            $state=STATE_IO;
            redo;
          }
        }
        elsif($state=STATE_IO){
          
          $res=Net::SSLeay::write $ssl, substr $buffer, $offset, $length;#, $length;
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
              Log::OK::DEBUG and log_debug "SSL_ERROR_NONE in syswrite";
            }
            elsif($res==SSL_ERROR_WANT_X509_LOOKUP){
              Log::OK::DEBUG and log_debug "SSL_ERROR_WANT_X509_LOOKUP in syswrite";
              last;
            }
            elsif($res== SSL_ERROR_SYSCALL){
              Log::OK::DEBUG and log_debug "SSL_ERROR_SYSCALL in syswrite";
              $res=undef;
              #$!=0;
              last;
            }
            elsif($res== SSL_ERROR_WANT_CONNECT){
              Log::OK::DEBUG and log_debug "SSL_ERROR_WANT_CONNECT in syswrite";
              last;
            }
            elsif($res== SSL_ERROR_WANT_ACCEPT){
              Log::OK::DEBUG and log_debug "SSL_ERROR_WANT_ACCEPT in syswrite";
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
              Log::OK::DEBUG and log_debug "some other ssl error in syswrite: $res";
              last;
            }

          }

        }
        else{
        }
      }
      $res;
  };

  ($sysread,$syswrite)
}
1;
