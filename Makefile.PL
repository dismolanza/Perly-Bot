package Perly::Bot;
use strict;
use warnings;

=encoding utf8

=head1 The build file for Perly::Bot

This build file is a modulino; it works as both a build script and
a module.

To build the distribution, run this file normally:

  % perl Makefile.PL

But, it's more interesting than that. You can load it with C<require>
and call C<arguments> to get the data structure it passes to
C<WriteMakefile>:

  my $package = require '/path/to/Makefile.PL';
  my $arguments = $package->arguments;

Note that C<require>-ing a file makes an entry in C<%INC> for exactly
that name. If you try to C<require> another file with the same name,
even from a different path, C<require> thinks it has already loaded
the file. As such, I recommend you always require the full path to the
file.

The return value of the C<require> is a package name (in this case,
the name of the main module. Use that to call the C<arguments> method.

Even if this distribution needs a higher version of Perl, this bit
only needs v5.8. You can play with the data structure with a primitive
Perl.

=cut

use File::Spec::Functions qw(catfile);

my $module = __PACKAGE__;
( my $dist = $module ) =~ s/::/-/g;

my $github = 'https://github.com/dnmfarrell/Perly-Bot';
my $main_file = catfile( 'lib', split /::/, "$module.pm" );

my %WriteMakefile = (
  'MIN_PERL_VERSION' => '5.010',

  'NAME'          => $module,
  'ABSTRACT_FROM' => $main_file,
  'VERSION_FROM'  => $main_file,
  'LICENSE'       => 'perl',
  'AUTHOR'        => 'David Farrell <dfarrell@cpan.org>',

  'EXE_FILES' => [qw( bin/perlybot )],

  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker'   => '6.64',
    'File::Spec::Functions' => '0',
  },

  'BUILD_REQUIRES' => {},

  'TEST_REQUIRES' => {
    'Test::More' => '0.94',
    'Test::Pod'  => '1.51',
  },

  'PREREQ_PM' => {
    'namespace::autoclean'            => '0',
    'CHI'                             => '0',
    'Carp'                            => '0',
    'Class::Accessor'                 => '0',
    'File::Spec::Functions'           => '0',
    'HTML::Entities'                  => '0',
    'JSON::XS'                        => '0',
    'Log::Log4perl'                   => '0',
    'Mojolicious'                     => '0',
    'Mojo::Snoo'                      => '0.14',
    'Net::Twitter::Lite::WithAPIv1_1' => '0.12006',
    'Net::OAuth'                      => '0.25',
    'Path::Tiny'                      => '0',
    'Time::Piece'                     => '0',
    'Time::Seconds'                   => '0',
    'XML::FeedPP'                     => '0',
    'YAML::XS'                        => '0',
  },

  'META_MERGE' => {
    'meta-spec' => { version => 2 },
    resources   => {
      repository => {
        type => 'git',
        url  => "$github.git",
        web  => $github,
      },
      bugtracker => {
        web => "$github/issues",
      },
      homepage => $github,
    },
  },

  clean => { FILES => "$dist-*" },
);

sub arguments { \%WriteMakefile }

do_it() unless caller;

sub do_it {
  require File::Spec;
  my $MM         = 'ExtUtils::MakeMaker';
  my $MM_version = eval {
    "$MM " . $WriteMakefile{'CONFIGURE_REQUIRES'}{'ExtUtils::MakeMaker'};
  }
    || "$MM 6.64";
  eval "use $MM_version; 1" or die "Could not load $MM_version: $@";
  eval "use Test::Manifest 1.21"
    if -e File::Spec->catfile(qw(t test_manifest));

  my $arguments = arguments();
  my $minimum_perl = $arguments->{MIN_PERL_VERSION} || '5.008';
  eval "require $minimum_perl;" or die $@;

  WriteMakefile(%$arguments);
}

no warnings;
__PACKAGE__;
