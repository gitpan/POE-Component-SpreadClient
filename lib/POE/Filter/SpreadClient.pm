# Declare our package
package POE::Filter::SpreadClient;
use strict; use warnings;

# Our version stuff
# $Revision: 1182 $
our $VERSION = '0.02';

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
