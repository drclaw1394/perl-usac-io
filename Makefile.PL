use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'uSAC::SIO',
    VERSION_FROM      => 'lib/uSAC/SIO.pm',
    PREREQ_PM         => {
    				enum=>0,
				AnyEvent=>0,
			}, # e.g., Module::Name => 1.1
    ABSTRACT_FROM     => 'lib/uSAC/SIO.pm', # retrieve abstract from module
    AUTHOR            => 'Ruben Westerberg <drclaw@mac.com>',
    LICENSE           => 'mit',
    #Value must be from legacy list of licenses here
    #https://metacpan.org/pod/Module::Build::API
);
