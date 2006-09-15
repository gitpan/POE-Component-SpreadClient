# Declare our package
package POE::Component::SpreadClient;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Our version stuff
# $Revision: 1164 $
our $VERSION = '0.01';

# Load our stuff
use POE qw( Wheel::ReadWrite );
use POE::Driver::SpreadClient;
use POE::Filter::SpreadClient;
use Spread qw( :MESS :ERROR );

# Other miscellaneous modules we need
use Carp;

# Generate our states!
use base 'POE::Session::AttributeBased';

# Set some constants
BEGIN {
	# Debug fun!
	if ( ! defined &DEBUG ) {
		eval "sub DEBUG () { 0 }";
	}
}

# Create our instance!
sub spawn {
    	# Get the OOP's type
	my $type = shift;

	# Our own options
	my $ALIAS = shift;

	# Get the session alias
	if ( ! defined $ALIAS ) {
		# Debugging info...
		if ( DEBUG ) {
			warn 'Using default ALIAS = SpreadClient';
		}

		# Set the default
		$ALIAS = 'SpreadClient';
	}

	# Okay, create our session!
	POE::Session::AttributeBased->create(
		'heap'	=>	{
			'ALIAS'		=>	$ALIAS,
		},
	) or croak;
}

sub _start : state {
	# Debugging
	if ( DEBUG ) {
		warn "SpreadClient was started!";
	}

	# Set our own alias
	if ( $_[KERNEL]->alias_set( $_[HEAP]->{'ALIAS'} ) != 0 ) {
		die "unable to set alias: " . $_[HEAP]->{'ALIAS'};
	}
}

sub _stop : state {
	# Debugging
	if ( DEBUG ) {
		warn "SpreadClient was stopped!";
	}

	# Wow, go disconnect ourself!
	$_[KERNEL]->call( $_[SESSION], 'disconnect' );
}

sub connect : state {
	# Server info, private name
	my( $server, $priv ) = @_[ ARG0, ARG1 ];

	# Tack on the default port if needed
	unless ( $server =~ /^\d+$/ or $server =~ /@/ ) {
		# Debugging
		if ( DEBUG ) {
			warn "using default port 4803";
		}

		$server = '4803@' . $server;
	}

	# Automatically set private name
	if ( ! defined $priv ) {
		# Debugging
		if ( DEBUG ) {
			warn "using default priv-name: spread-PID";
		}

		$priv = 'spread-' . $$;
	}

	# Automatically add the sender session to listeners
	if ( ! exists $_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } ) {
		$_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } = 1;
	}

	# Fire up Spread itself
	my( $mbox, $priv_group );
	eval {
		( $mbox, $priv_group ) = Spread::connect( {
			'private_name'	=>	$priv,
			'spread_name'	=>	$server,
		} );
	};
	if ( $@ ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', 'CONNECT', $@, $server, $priv );
		}
	} else {
		# Sanity
		if ( ! defined $mbox ) {
			# Inform our registered listeners
			foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
				$_[KERNEL]->post( $l, '_sp_error', 'CONNECT', $sperrno, $server, $priv );
			}
		} else {
			# Set our data
			$_[HEAP]->{'SERVER'} = $server;
			$_[HEAP]->{'PRIV_NAME'} = $priv;
			$_[HEAP]->{'PRIV_GROUP'} = $priv_group;
			$_[HEAP]->{'MBOX'} = $mbox;

			# Create a FH to feed into Wheel::ReadWrite
			open $_[HEAP]->{'FH'}, "<&=$mbox";

			# Finally, create the wheel!
			$_[HEAP]->{'WHEEL'} = POE::Wheel::ReadWrite->new(
				'Handle'	=> $_[HEAP]->{'FH'},
				'Driver'	=> POE::Driver::SpreadClient->new( $mbox ),
				'Filter'	=> POE::Filter::SpreadClient->new(),

				'InputEvent' => 'RW_GotPacket',
				'ErrorEvent' => 'RW_Error'
			);

			# Inform our registered listeners
			foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
				$_[KERNEL]->post( $l, '_sp_connect', $priv, $priv_group );
			}
		}
	}

	# All done!
	return;
}

sub disconnect : state {
	# Sanity
	if ( ! exists $_[HEAP]->{'DISCONNECTED'} ) {
		# Sanity
		if ( exists $_[HEAP]->{'WHEEL'} and defined $_[HEAP]->{'WHEEL'} ) {
			# Debugging
			if ( DEBUG ) {
				warn "SpreadClient is disconnecting!";
			}

			# Shutdown the input/output
			$_[HEAP]->{'WHEEL'}->shutdown_input();
			$_[HEAP]->{'WHEEL'}->shutdown_output();

			# Get rid of it!
			undef $_[HEAP]->{'WHEEL'};
		}

		# Inform our registered listeners
		# XXX Should I use POST here instead?
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->call( $l, '_sp_disconnect', $_[HEAP]->{'PRIV_NAME'} );
		}

		# Get rid of our alias
		$_[KERNEL]->alias_remove( $_[HEAP]->{'ALIAS'} );

		# Set it in our heap that we've disconnected
		$_[HEAP]->{'DISCONNECTED'} = 1;
	}

	# All done!
	return;
}

sub publish : state {
	my( $groups, $message, $mess_type ) = @_[ ARG0 .. ARG2 ];

	# Shortcut
	if ( ! defined $_[HEAP]->{'WHEEL'} ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', 'PUBLISH', CONNECTION_CLOSED, $groups, $message );
		}

		# All done!
		return;
	}

	# Sanity
	if ( ! defined $mess_type ) {
		$mess_type = 0;
	}

	# Send it!
	my $rtn;
	eval {
		$rtn = Spread::multicast( $_[HEAP]->{'MBOX'}, SAFE_MESS, $groups, $mess_type, $message );
	};
	if ( $@ or ! defined $rtn or $rtn < 0 ) {
		# Check for disconnect
		if ( defined $sperrno and $sperrno == CONNECTION_CLOSED ) {
			$_[KERNEL]->call( $_[SESSION], 'disconnect' );
		}

		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', 'PUBLISH', $sperrno, $groups, $message );
		}
	}

	# All done!
	return;
}

sub subscribe : state {
	# The groups to join
	my $groups = $_[ARG0];

	# Shortcut
	if ( ! defined $_[HEAP]->{'WHEEL'} ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', 'SUBSCRIBE', CONNECTION_CLOSED, $groups );
		}

		# All done!
		return;
	}

	# Automatically add the sender session to listeners
	if ( ! exists $_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } ) {
		$_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } = 1;
	}

	# Actually join!
	my $rtn;
	eval {
		$rtn = Spread::join( $_[HEAP]->{'MBOX'}, $groups );
	};
	if ( $@ or ! $rtn ) {
		# Check for disconnect
		if ( defined $sperrno and $sperrno == CONNECTION_CLOSED ) {
			$_[KERNEL]->call( $_[SESSION], 'disconnect' );
		}

		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', 'SUBSCRIBE', $sperrno, $groups );
		}
	}

	# All done!
	return;
}

sub unsubscribe : state {
	# The groups to unsub
	my $groups = $_[ARG0];

	# Shortcut
	if ( ! defined $_[HEAP]->{'WHEEL'} ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', 'UNSUBSCRIBE', CONNECTION_CLOSED, $groups );
		}

		# All done!
		return;
	}

	# Actually join!
	my $rtn;
	eval {
		$rtn = Spread::leave( $_[HEAP]->{'MBOX'}, $groups );
	};
	if ( $@ or ! $rtn ) {
		# Check for disconnect
		if ( defined $sperrno and $sperrno == CONNECTION_CLOSED ) {
			$_[KERNEL]->call( $_[SESSION], 'disconnect' );
		}

		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', 'UNSUBSCRIBE', $sperrno, $groups );
		}
	}

	# All done!
	return;
}

# Registers interest in the client
sub register : state {
	# Automatically add the sender session to listeners
	if ( ! exists $_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } ) {
		$_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } = 1;
	}

	# All done!
	return;
}

# Unregisters interest in the client
sub unregister : state {
	# Automatically add the sender session to listeners
	if ( exists $_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } ) {
		delete $_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID };
	}

	# All done!
	return;
}

sub RW_Error : state {
	# ARG0 = operation, ARG1 = error number, ARG2 = error string, ARG3 = wheel ID
	my ( $operation, $errnum, $errstr, $id ) = @_[ ARG0 .. ARG3 ];

	# Debugging
	if ( DEBUG and $errnum != 0 ) {
		warn "ReadWrite wheel($id) got error $errnum - $errstr doing $operation";
	}

	# Disconnect now!
	$_[KERNEL]->call( $_[SESSION], 'disconnect' );
}

sub RW_GotPacket : state {
	my( $type, $sender, $groups, $mess, $endian, $message ) = @{ @{ $_[ARG0] }[0] };

	# Check for disconnect
	if ( ! defined $type ) {
		# Disconnect now!
		$_[KERNEL]->call( $_[SESSION], 'disconnect' );
	} else {
		# Check the type
		if ( $type & REGULAR_MESS ) {
			# Regular message
			foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
				$_[KERNEL]->post( $l, '_sp_message', $_[HEAP]->{'PRIV_NAME'}, $type, $sender, $groups, $mess, $message );
			}
		} else {
			# Admin message
			foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
				$_[KERNEL]->post( $l, '_sp_admin', $_[HEAP]->{'PRIV_NAME'}, $type, $sender, $groups, $mess, $message );
			}
		}
	}

	# All done!
	return;
}

1;
__END__

=head1 NAME

POE::Component::SpreadClient - handle Spread communications in POE

=head1 SYNOPSIS

    POE::Component::SpreadClient->spawn( 'spread' );

    POE::Session->create(
        inline_states => {
            _start => \&_start,
            _sp_message => \&do_something,
            _sp_admin => \&do_something,
            _sp_connect => \&do_something,
            _sp_disconnect => \&do_something,
            _sp_error => \&do_something,
        }
    );

    sub _start {
        $poe_kernel->alias_set('displayer');
        $poe_kernel->post( spread => connect => 'localhost', $$ );
        $poe_kernel->post( spread => subscribe => 'chatroom' );
        $poe_kernel->post( spread => publish => 'chatroom', 'A/S/L?' );
    }

=head1 DESCRIPTION

POE::Component::SpreadClient is a POE component for talking to Spread servers.

=head1 METHODS

=head2 spawn

    POE::Component::Spread->spawn( 'spread' );

    - The alias the component will take ( default: "SpreadClient" )

=head1 Public API

=head2 connect

    $poe_kernel->post( spread => connect => '4444@localhost' );
    $poe_kernel->post( spread => connect => '4444@localhost', 'logger' );

    - The Server location
    - The private name for the Spread connection ( default: "spread-PID" )

Connect this POE session to the Spread server on port 4444 on localhost.

=head2 disconnect

	$poe_kernel->post( spread => disconnect );

Forces this session to disconnect and remove it's alias.

=head2 subscribe

    $poe_kernel->post( spread => subscribe => 'chatroom' );
    $poe_kernel->post( spread => subscribe => [ 'chatroom', 'testing' ] );

    - The group name(s)

Subscribe to a Spread messaging group. Messages will be sent to C<_sp_message> and
C<_sp_admin> events in the registered listeners.

Automatically adds the session to the registered listeners.

=head2 unsubscribe

	$poe_kernel->post( spread => unsubscribe => 'chatroom' );
	$poe_kernel->post( spread => unsubscribe => [ 'foobar', 'chatroom' ] );

Unsubscribes to a Spread messaging group. Does not remove the session from the listener list.

=head2 publish

    $poe_kernel->post( spread => publish => 'chatroom', 'A/S/L?' );
    $poe_kernel->post( spread => publish => [ 'chatroom', 'stats' ], 'A/S/L?' );
    $poe_kernel->post( spread => publish => 'chatroom', 'special', 5 );

    - The group name(s)
    - Adding the last parameter ( int ) is the Spread mess_type -> application-defined ( default: 0 )

Send a simple message to a Spread group(s).

=head2 register

	$poe_kernel->post( spread => register );

Registers the current session as a "registered listener" and will receive all events.

=head2 unregister

	$poe_kernel->post( spread => unregister );

Removes the current session from the "registered listeners" list.

=head1 EVENTS

=head2 C<_sp_connect>

	sub _sp_connect : state {
		my( $priv_name, $priv_group ) = @_[ ARG0, ARG1 ];
		# We're connected!
	}

=head2 C<_sp_disconnect>

	sub _sp_disconnect : state {
		my $priv_name = $_[ ARG0 ];
		# We're disconnected!
	}

=head2 C<_sp_error>

	sub _sp_error : state {
		my( $type, $sperrno, $msg, $data ) = @_[ ARG0 .. ARG3 ];

		# Handle different kinds of errors
		if ( $type eq 'CONNECT' ) {
			# $sperrno = error string, $msg = server name, $data = priv name
		} elsif ( $type eq 'PUBLISH' ) {
			# $sperrno = Spread errno, $msg = $groups, $data = $message
		} elsif ( $type eq 'SUBSCRIBE' ) {
			# $sperrno = Spread errno, $msg = $groups
		} elsif ( $type eq 'UNSUBSCRIBE' ) {
			# $sperrno = Spread errno, $msg = $groups
		}
	}

=head2 C<_sp_message>

	sub _sp_message : state {
		my( $priv_name, $type, $sender, $groups, $mess_type, $message ) = @_[ ARG0 .. ARG5 ];

		# $type is always REGULAR_MESS
		# $mess_type is 0 unless defined ( mess_type in Spread )
	}

=head2 C<_sp_admin>

	sub _sp_admin : state {
		my( $priv_name, $type, $sender, $groups, $mess_type, $message ) = @_[ ARG0 .. ARG5 ];
		# Could be somebody quit/join or something else?
	}

=head2 SpreadClient Notes

You can enable debugging mode by doing this:

	sub POE::Component::SpreadClient::DEBUG () { 1 }
	use POE::Component::SpreadClient;

=head1 BUGS

- Need to expand documentation so the message types in _sp_admin is more understandable
- Would love to have more message handling - a simple look at the Spread User's Guide shows a lot of message variety!
- Need to be tested more!

=head1 SEE ALSO

L<Spread>

L<POE::Component::Spread>

=head1 CREDITS

The base for this module was lifted from POE::Component::Spread by
Rob Partington <perl-pcs@frottage.org>.

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
