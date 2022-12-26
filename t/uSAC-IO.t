use strict;
use warnings;
use feature qw<refaliasing current_sub say>;

use AnyEvent;
use Test::More tests => 1;
BEGIN { use_ok('uSAC::IO') };

