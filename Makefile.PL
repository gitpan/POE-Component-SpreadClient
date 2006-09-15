use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	NAME			=> 'POE::Component::SpreadClient',
	VERSION_FROM		=> 'lib/POE/Component/SpreadClient.pm', # finds $VERSION
	PREREQ_PM		=> {
		'POE'				=>	'0.37',
		'Spread'			=>	0,
		'POE::Session::AttributeBased'	=>	0,
		'Test::More'			=>	0,
	},
	($] >= 5.005 ?     ## Add these new keywords supported since 5.005
		(ABSTRACT_FROM  => 'lib/POE/Component/SpreadClient.pm', # retrieve abstract from module
		AUTHOR         => 'Apocalypse <APOCAL@cpan.org>') : ()),
);
