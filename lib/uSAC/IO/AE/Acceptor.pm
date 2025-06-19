use Object::Pad;

package uSAC::IO::AE::Acceptor;

#Only force a nonblocking setting if needed. ie linux => true
#     bsd and dawrwin false
#     others true
use constant::more SET_NONBLOCKING=>$^O =~ "darwin"? 1 : $^O =~ "linux"?1:1;

use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use AnyEvent;

use IO::FD;

class uSAC::IO::AE::Acceptor :isa(uSAC::IO::Acceptor);

use feature qw<refaliasing current_sub>;
no warnings qw<experimental uninitialized>;
field $_aw;
field $_acceptor;
		
field $_afh_ref;

BUILD {
	$_afh_ref=\$self->fh;
}

method start :override ($fh=undef){
	$$_afh_ref=$fh if $fh;
	$_aw= AE::io $$_afh_ref, 0, $_acceptor//=$self->_make_acceptor;
  $uSAC::IO::AE::IO::watchers{$self}=$_aw;
	$self;
}

method _make_acceptor :override {

  \my $on_accept=\$self->on_accept; #alias the accept callback
  \my $on_error=\$self->on_error; #alias the error callback
  $_aw=undef; #Ensure watcher is dead
  \my $afh=$_afh_ref;
  #my @new; my $new=\@new;
  #my @peers; my $peers=\@peers;

  #Return a sub which is used in the AE::io call
  sub {
    my $new=[];
    my $peers=[];
    my $res= IO::FD::accept_multiple @$new, @$peers, $afh;
    if(defined $res){ 
      if(SET_NONBLOCKING){ 
        IO::FD::fcntl $_, F_SETFL, O_NONBLOCK for @$new;
      }
      #execute the callback with the array refs and the actuall listening fd
      $on_accept->($new, $peers, $afh);
    }
    else {
      $on_error->($!);
    }
  }
}

method pause :override {
  #Destroy the IO watcher
  undef $_aw;
  delete $uSAC::IO::AE::IO::watchers{$self};
}

1;
