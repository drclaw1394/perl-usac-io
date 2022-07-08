use Object::Pad;
class uSAC::IO::Writer;
use feature qw<refaliasing current_sub say>;
no warnings qw<experimental uninitialized>;

use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use AnyEvent;
use Log::ger;
use Log::OK;
use Errno qw(EAGAIN EINTR);

field $_ctx;
field $_wfh :param :mutator;
field $_time :mutator;
field $_clock :mutator;
field $_on_drain;
field $_on_eof;
field $_on_error :mutator;
field $_writer;
field @_queue; 

BUILD {
        fcntl $_wfh, F_SETFL, O_NONBLOCK;
	$_on_drain//=$_on_error//=method{};
	#$self->[writer_]=undef;
	#@_queue;
	my $time=0;

	$_time=\$time;
	$_clock=\$time;

}

ADJUST {
	#make a writer
	$_writer=$self->_make_writer;

}
method timing {
	($_time, $_clock)=@_;
}

#return or create an return writer
method writer {
	$_writer//=$self->_make_writer;
}

#OO interface
method write {
	&{$_writer};
}



###############################
# method on_eof : lvalue {    #
#         $_[0][on_eof_]->$*; #
# }                           #
###############################


method on_drain : lvalue{
	$_on_drain;
}


#SUB CLASS SPECIFIC
#
method pause {

}

method set_write_handle {

}

method _make_writer {
	say "IN IO WRITER make writer";
}

method queue {
	\@_queue;
}

1;

