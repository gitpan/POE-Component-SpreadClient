#
# This file is part of POE-Component-SpreadClient
#
# This software is copyright (c) 2011 by Apocalypse.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
use strict; use warnings;
package POE::Driver::SpreadClient;
BEGIN {
  $POE::Driver::SpreadClient::VERSION = '1.002';
}
BEGIN {
  $POE::Driver::SpreadClient::AUTHORITY = 'cpan:APOCAL';
}

# ABSTRACT: Implements the Spread driver for POE

# Import some stuff
use Spread;

use constant MAX_READS => 256;

sub new {
	my $type = shift;
	my $mbox = shift;
	my $self = bless \$mbox, $type;
	return $self;
}

sub get {
	my $self = shift;

	my $reads_performed = 1;
	my @buf = ();

	# read once:
	push @buf, [ Spread::receive( $$self ) ];

	# Spread::poll returns 0 if no messages pending;
	while( Spread::poll( $$self ) and ++$reads_performed <= MAX_READS ) {
		push @buf, [ Spread::receive( $$self ) ];
	}

	return [ @buf ];
}

1;


__END__
=pod

=head1 NAME

POE::Driver::SpreadClient - Implements the Spread driver for POE

=head1 VERSION

  This document describes v1.002 of POE::Driver::SpreadClient - released February 16, 2011 as part of POE-Component-SpreadClient.

=head1 DESCRIPTION

This module implements the L<POE::Driver> interface for Spread.

=head1 SEE ALSO

Please see those modules/websites for more information related to this module.

=over 4

=item *

L<POE::Component::SpreadClient>

=back

=head1 AUTHOR

Apocalypse <APOCAL@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Apocalypse.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the LICENSE file included with this distribution.

=cut

