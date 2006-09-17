# Declare our package
package POE::Filter::SpreadClient;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Our version stuff
# $Revision: 1182 $
our $VERSION = '0.01';

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
