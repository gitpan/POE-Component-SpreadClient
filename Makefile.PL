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
	(	$] >= 5.005 ?		# Add new keywords
		(
			'ABSTRACT_FROM'	=> 'lib/POE/Component/SpreadClient.pm', # retrieve abstract from module
			'AUTHOR'	=> 'Apocalypse <APOCAL@cpan.org>',
		) : ()
	),

	# Thanks POE!
	'dist'		=> {
		'PREOP'		=> (
			"echo 'license: perl' >> ./META.yml;" .
			'/bin/cp -f ./META.yml ./$(DISTNAME)-$(VERSION)/META.yml &2>/dev/null'
		),
	},
);
