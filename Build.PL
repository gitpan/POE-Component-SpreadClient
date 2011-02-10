
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  'build_requires' => {
    'File::Find' => '0',
    'File::Temp' => '0',
    'Module::Build' => '0.3601',
    'Test::More' => '0.88'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Handle Spread communications in POE',
  'dist_author' => [
    'Apocalypse <APOCAL@cpan.org>'
  ],
  'dist_name' => 'POE-Component-SpreadClient',
  'dist_version' => '1.000',
  'license' => 'perl',
  'module_name' => 'POE::Component::SpreadClient',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'POE' => '0',
    'POE::Session' => '0',
    'POE::Session::AttributeBased' => '0',
    'POE::Wheel::ReadWrite' => '0',
    'Spread' => '3.017',
    'constant' => '0',
    'perl' => '5.006'
  },
  'script_files' => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
