use strict;
use warnings;
use feature qw<refaliasing current_sub say>;

use AnyEvent;
use Test::More tests => 1;
use uSAC::Loaded;
BEGIN { use_ok('uSAC::IO') };

