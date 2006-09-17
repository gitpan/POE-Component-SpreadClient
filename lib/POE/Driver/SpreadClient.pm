# Declare our package
package POE::Driver::SpreadClient;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Our version stuff
# $Revision: 1182 $
our $VERSION = '0.01';

# Import some stuff
use Spread;

sub new {
	my $type = shift;
	my $mbox = shift;
	my $self = bless \$mbox, $type;
	return $self;
}

sub get {
	my $self = shift;

	# this returns all undef if we're disconnected
	return [ [ Spread::receive( $$self ) ] ];
}

1;
__END__
