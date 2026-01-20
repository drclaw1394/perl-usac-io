package uSAC::Loaded;

# Soul purpose is to load this module from usac command line  and set this variable
#
# This is checked by uSAC::IO at import to ensure it loaded correcly
#
# The goal is to ensure that usac scripts are loaded by usac and give a nice
# error when loaded by perl directly
#
our $Loaded=1;

1;
