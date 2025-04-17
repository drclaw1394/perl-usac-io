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
				AnyEvent=>0,
				"IO::FD"=>"v0.3.7",
				"Log::ger"=>0,
				"Log::OK"=>0,
				"Object::Pad"=>0,
        "Socket::More::Resolver"=>0,
        "Socket::More"=>0,
        "Error::Show"=>0,
	"Data::Dump::Color"=>0,
  "uSAC::FastPack"=>0

			}, 
    ABSTRACT_FROM     => 'lib/uSAC/IO.pod', 
    AUTHOR            => 'Ruben Westerberg <drclaw@mac.com>',
    LICENSE           => 'mit',
);
