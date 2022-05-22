use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'uSAC::SIO',
    VERSION_FROM      => 'lib/uSAC/SIO.pm',
    MIN_PERL_VERSION  => '5.24.0',
    PREREQ_PM         => {
    				enum=>0,
				AnyEvent=>0,
				"Log::ger"=>0,
				"Log::OK"=>0
			}, 
    ABSTRACT_FROM     => 'lib/uSAC/SIO.pm', 
    AUTHOR            => 'Ruben Westerberg <drclaw@mac.com>',
    LICENSE           => 'mit',
);
