use uSAC::IO;

use Data::Dumper;
use Devel::MAT::Dumper;
use feature ":all";

sub error {
  adump $STDERR, "Got error ", @_;
}

my $fid;
my $counter=100000;

my $head;
$head= linker io_file_slurp(\&error), sub {
  say "Counter: ",$counter--; 
  
  unless($counter){
    Devel::MAT::Dumper::dump("pmay.dat");
    exit;
  }
  #say STDERR "fid: $fid,,,,DISPATCH";
  #say STDERR Dumper @_; 
  asap sub {$head->( [{path=>"test.txt", mode=>"<"}], undef)};
};

$head->( [{path=>"test.txt", mode=>"<"}], undef);
