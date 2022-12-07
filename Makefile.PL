use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'uSAC::IO',
    VERSION_FROM      => 'lib/uSAC/IO.pm',
    MIN_PERL_VERSION  => '5.24.0',
    PREREQ_PM         => {
    				enum=>0,
				AnyEvent=>0,
				"IO::FD"=>"0.1.3",
				"Log::ger"=>0,
				"Log::OK"=>0
			}, 
    ABSTRACT_FROM     => 'lib/uSAC/IO.pod', 
    AUTHOR            => 'Ruben Westerberg <drclaw@mac.com>',
    LICENSE           => 'mit',
);
