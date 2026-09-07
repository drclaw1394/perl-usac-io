package uSAC::Util;
use strict;
use warnings;
# Utility functions


use Export::These qw( cwd dirname basename path catfile abs2rel rel2abs dost need hashed_path);# decode_urlencoded_form);

sub cwd {
  my($dev, $inode)=stat ".";
  #my ($odev, $oinode)=($dev, $inode);

  my($prev_dev, $prev_inode)=(-1,-1);
  my @parts;
  until($prev_dev == $dev and $prev_inode == $inode){
      die $! unless chdir "..";

      my ($tdev, $tinode);

      ########################################################################
      # This is much nicer code, but requires alot more memory for code
      # for my $name (<*>){                                                  #
      #   ($tdev, $tinode)=lstat $name;                                      #
      #   push @parts, $name and last if($tdev == $dev and $tinode==$inode); #
      # }                                                                    #
      ########################################################################

      opendir my $dir, ".";
      my @list= readdir $dir;
      closedir $dir;
      
      #while(readdir $dir){
      for(@list){
        next if $_ eq "." or $_ eq "..";
        ($tdev, $tinode)=lstat;
        push @parts, $_ and last if($tdev == $dev and $tinode==$inode);
      }
      #closedir $dir;

      $prev_dev=$dev;
      $prev_inode=$inode;

      ($dev, $inode)=stat ".";
  }
  my $cwd="/".join "/", reverse @parts;
  chdir $cwd; #Change back
  $cwd
}

sub rel2abs {
  my $path=shift;
  my $base=shift||cwd;
  if($base !~ m|^/|){
    $base=abs2rel $base;
  }
  $base."/".$path;

}

sub abs2rel {
  my $abs=shift;
  my $base=shift||cwd;

  if($base !~ m|^/|){
    $base=abs2rel $base;
  }

  #find longest prefix
  my @base=split "/", $base;

  my $longest="";
  my $found=0;

  for(0..$#base){
    $longest=join "/", @base[0..$_];
    last if index $abs, $longest;
    $found++;
  }
  my $back_count=@base-$found;

  #strip off longest
  
  my $p=substr $abs,  length $longest;
  $p=join "/", ("..")x$back_count, $p;
  
  my @abs=split "/", $p;

  $p=substr $p, 1;
  # Prepend backcount

  #############################################################
  # my $index= index  $abs, $base;                            #
  #                                                           #
  # my @items=split "/", substr $abs, $index+length($base)+1; #
  # join "/", @items;                                         #
  #############################################################
  $p;

}

sub basename {
  my $path=shift;
  my @items = split "/", $path;
  pop @items;
}

sub dirname {
  my $path=shift;
  my @items = split "/", $path;
  my $p;
  if(@items>1){
    pop @items;
    $p=join "/", @items;
  }
  else {
    $p=".";# if @items == 1;
  }
  $p;
  
}


# Process a path.  
# If a ref and defined, make relative to caller dir
# If a ref and undefined, is caller dir
# if a ref and abs leave as it is
# if not a ref and defined make relative to cwd
# if not a ref and undefined is relative caller dir
# if not a ref and abs leave as it is
#
# Optional second argument specifiy caller frame. If none proveded is
# assumed to be direct caller of this sub
# 
sub path {
  my $p;
  my $prefix;
  my $frame=$_[1]//[caller];

  
  my $cwd= cwd;#`realpath`;
  
  if(ref($_[0]) eq "SCALAR" or !defined $_[0]){
    $prefix=dirname abs2rel rel2abs $frame->[1];

    #Create the root as a relative path to current working dir
    
    if($_[0]){
      # Defined scalar refererence. Dereference it
      $p=$_[0]->$*;
      return $p if $p =~ m|^/|;
      $p="$prefix/$p";
    }
    else{
      # Undefined input, use caller dir only
      # No prefix specified, don't join
      $p=$prefix;
    }
  }

  else {
    # Path is either CWD relative or absolute
    $p=$_[0];#$prefix;#$_[0];
  }

  if($p=~m|^/|){
    # ABS path. No nothing
  }
  elsif($p eq "."){
    $p="./"
  }
  elsif($p eq ".."){
    $p="../"
  }
  elsif($p!~m|^\.+/|){
    #relative path, but no leading dot slash. Add one to help 'require'
    $p="./".$p;
  }
  $p;
}

*usac_path=\&path;

# Modified version of perl 'do'. Allow using caller relative paths
# Executes in callers namespace
#
sub dost(*) {
  my @c=caller;
  local $@;
  eval "
  package $c[0];
  do &path;
  ";
}

my %needed;

# This was supposed to be a better require and always return the last value when requiring a script.
# But in reality it really on if the script or moudle is 'used' or 'required' beforehand, the return value is lost.
#
# In this case it attempts to return the package name
#
#
sub need (*) {
  my $input=shift;
  my $frame=shift//[caller];

  # Resolve any relative to caller file paths
  # Wrapper around require. Exactly like require, exect the last value (the true value) is remembered
  my $res;
  my $key;

  my $path=$input;
  my $bare;
  for($path){
    # If the target contains :: or does not end with .pm, then 
    # assume it was a 'bare word' module
    if(!ref and (s|::|/|g or !/\./)){
      # Convert module name to path
      $key.=$_.".pm";
      $bare=1;
    }
    else{
      # Input is treated as path
      $key= path $input, $frame;
    }
  } 

  # Check the needed hash for the filename
  if(exists $needed{$key}){
    $res=$needed{$key};
  }
  else{
    if($bare){
      my @c=caller;
      local $@;
      $res=eval "
        package $c[0];
        require $input;
        ";
      die $@ if $@;
    }
    else {
      # Set package to caller
      my @c=caller;
      local $@;
      $res=eval "package $c[0];
      require (\"$key\");
      ";
      die "$!
      $@
      " if $@;

      
      #local $@;
      #$res=require ($key);
      die "Could not require non bare word need" unless $res;
    }
      if(ref $res ){
        # First time loaded, and any ref.. 
         uSAC::IO::adump($STDERR, "first time loaded ref", $key, $res);
      }
      elsif( $res == 1){
         # likely loaded previously. user package name
         uSAC::IO::adump($STDERR, "loaded res is 1", $key, $res);
         $res=$input;
      }
      else {
         # Non ref.. packagename?
         uSAC::IO::adump($STDERR, "loaded non reference", $key, $res);
         #$res=$input;
      }
    $needed{$key}=$res;
  }
  uSAC::IO::adump($STDERR, " ---- END OF NEED", $key, $res);
  $res;
}


sub catfile {
  # Make sure no trailing slashses on components, then join
  join "/", map s|/$||, @_;
}



use Digest::SHA qw<sha256>;
use MIME::Base64;
use UUID qw<generate_v4>;


# Generate a hash for a file name (or path) and  optionally create a mutlilevel dir structure to with new file name
# If no name/path is given, a random one is generated and is used as the orginal name
# The create flag is used to actuall create the dir strutures. otherwise a hash is just calculated
# 
# root dir is the root dir to use . is the current working dir if not specified
#
#
# In scalar context returns the hashed path
# In list context returns the original name and the hased path

sub hashed_path {

  my $org_path=shift//"";         # The filename to process
  my $root_dir=shift//".";   # The root dir to create directorires. Current dir by default
  my $create=shift;       # Create the dirs, otherwise just do a lookup
  my $new_ext=shift;

  my $want_random=!$org_path;   # If no original path, we want a fresh, random, unique filename generated

  
RANDOM_NAME: 

  # Create a new file name if one isn't provided, use the new extention if provdied
  if($want_random){
    generate_v4($org_path);
    $org_path=MIME::Base64::encode_base64url $org_path;
    $org_path.=".$new_ext" if $new_ext;
  }

  # Extract extention if it exists
  my $index=rindex $org_path, ".";
  my $ext="";
  if($index>=0){
    $ext=lc substr $org_path, $index+1;
    $ext=".$ext" if $ext;
  }
  
  my $path=$org_path;


  # Hash and the filename data an encode into base 64 (url)
  # This ensures a filename which allway has a length
  use utf8;
  #my $temp=utf8::encode $path;
  utf8::encode $path;
  #adump $STDERR, $temp;
  my $enc_path=MIME::Base64::encode_base64url sha256 $path;
  
  # append the extensino

  my $l1=substr $enc_path, 0, 3;
  my $l2=substr $enc_path, 3, 3;

  # if asked for a random name, we need to make sure case sensitve file systems
  # don't cause issues with an already existing file
  
  $path="$l1/$l2/$enc_path$ext";
  
  # Test if file name exists only if it was a randomly generated one
  if ($want_random and -e "$root_dir/$path"){
    goto RANDOM_NAME;
  }

  if($create){
    #adump $STDERR, "---file", $l1, $l2, "file name $h->{_filename}";

    my $p="$root_dir/$l1";
    (! -e $p) and (mkdir $p or die "$p --- $!");
    $p.="/$l2";

    (!-e $p) and (mkdir $p or die $!);
  }

  # Attempt tto add file extension

  # In scalar return the last element in the list, which is the new path)l
  ($org_path, $path);  #url level relative to dir

}

1;
