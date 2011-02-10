#
# This file is part of POE-Component-SpreadClient
#
# This software is copyright (c) 2011 by Apocalypse.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
use strict; use warnings;
package POE::Filter::SpreadClient;
BEGIN {
  $POE::Filter::SpreadClient::VERSION = '1.001';
}
BEGIN {
  $POE::Filter::SpreadClient::AUTHORITY = 'cpan:APOCAL';
}

# ABSTRACT: Implements the Spread filter for POE

sub new {
    my $type = shift;
    my $self = bless \$type, $type;
    return $self;
}

sub get {
    my $self = shift;
    return [ @_ ];
}

1;


__END__
=pod

=head1 NAME

POE::Filter::SpreadClient - Implements the Spread filter for POE

=head1 VERSION

  This document describes v1.001 of POE::Filter::SpreadClient - released February 09, 2011 as part of POE-Component-SpreadClient.

=head1 DESCRIPTION

This module implements the L<POE::Filter> interface for Spread.

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

