requires "POE" => "0";
requires "POE::Session" => "0";
requires "POE::Session::AttributeBased" => "0";
requires "POE::Wheel::ReadWrite" => "0";
requires "Spread" => "3.017";
requires "parent" => "0";
requires "perl" => "5.006";
requires "strict" => "0";
requires "warnings" => "0";

on 'test' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "File::Spec" => "0";
  requires "File::Temp" => "0";
  requires "IO::Handle" => "0";
  requires "IPC::Open3" => "0";
  requires "Test::More" => "0";
  requires "perl" => "5.006";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "Module::Build::Tiny" => "0.039";
  requires "perl" => "5.006";
};