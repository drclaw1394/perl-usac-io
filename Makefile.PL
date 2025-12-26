use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'uSAC::IO',
    VERSION_FROM      => 'lib/uSAC/IO.pm',
    MIN_PERL_VERSION  => '5.36.0',
    EXE_FILES         => [
                          "script/usac",
                          "script/usac-repl"
    ],
    PREREQ_PM         => {
      AnyEvent        =>0,
      "IO::FD"        =>"v0.3.7",
      "Log::ger"      =>0,
      "Log::ger::Output::Screen"=>0,
      "Log::OK"       =>0,
      "Object::Pad"   =>0,
      "Socket::More::Resolver"=>0,
      "Socket::More"  =>0,
      "Error::Show"   =>0,
      "Data::Dump::Color"=>0,
      "Sub::Middler"  =>v0.4.0,
      "Data::FastPack"=>v0.3.0,
      "List::Insertion"=>v0.2.1,
      "Cpanel::JSON::XS"=>0,
      "Data::MessagePack"=>0,

    }, 

    ABSTRACT_FROM     => 'lib/uSAC/IO.pod', 
    AUTHOR            => 'Ruben Westerberg <drclaw@mac.com>',
    LICENSE           => 'mit',

    META_ADD => {
      "meta-spec" => {
        version => 2
      },

      resources=> {
        repository =>{
          type => "git",
          url => "git://github.com/drclaw1394/perl5-usac-io.git",
          web => "https://github.com/drclaw1394/perl5-usac-io",
        }
      }
    }
  );
