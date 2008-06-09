use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	NAME			=> 'POE::Component::SpreadClient',
	VERSION_FROM		=> 'lib/POE/Component/SpreadClient.pm', # finds $VERSION
	PREREQ_PM		=> {
		'POE'		=>	'0.37',
			'POE::Session::AttributeBased'	=>	'0.07',
			'POE::Wheel::ReadWrite'		=>	0,

		'Spread'	=>	'3.17',
		'Carp'		=>	0,

		'Test::More'	=>	0,
	},
	(	$] >= 5.005 ?		# Add new keywords
		(
			'ABSTRACT_FROM'	=> 'lib/POE/Component/SpreadClient.pm', # retrieve abstract from module
			'AUTHOR'	=> 'Apocalypse <APOCAL@cpan.org>',
			'LICENSE'	=> 'perl',
		) : ()
	),
);
