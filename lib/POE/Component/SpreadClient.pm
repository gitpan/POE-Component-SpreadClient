#
# This file is part of POE-Component-SpreadClient
#
# This software is copyright (c) 2011 by Apocalypse.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
use strict; use warnings;
package POE::Component::SpreadClient;
BEGIN {
  $POE::Component::SpreadClient::VERSION = '1.001';
}
BEGIN {
  $POE::Component::SpreadClient::AUTHORITY = 'cpan:APOCAL';
}

# ABSTRACT: Handle Spread communications in POE

# Load our stuff
use 5.006;	# to silence Perl::Critic's Compatibility::ProhibitThreeArgumentOpen
use POE;
use POE::Session;
use POE::Wheel::ReadWrite;
use POE::Driver::SpreadClient;
use POE::Filter::SpreadClient;
use Spread 3.017 qw( :MESS :ERROR );

# Generate our states!
use base 'POE::Session::AttributeBased';

# Set some constants
BEGIN {
	if ( ! defined &DEBUG ) { *DEBUG = sub () { 0 } }
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
	my $sess = POE::Session->create(
		__PACKAGE__->inline_states(),		## no critic ( RequireExplicitInclusion )
		'heap'	=>	{
			'ALIAS'		=>	$ALIAS,
		},
	);

	# return the session's ID in case the caller needs it
	return $sess->ID;
}

sub _start : State {
	# Debugging
	if ( DEBUG ) {
		warn "SpreadClient was started!";
	}

	# Set our own alias
	if ( $_[KERNEL]->alias_set( $_[HEAP]->{'ALIAS'} ) != 0 ) {
		die "unable to set alias: " . $_[HEAP]->{'ALIAS'};
	}

	return;
}

sub _stop : State {
	# Debugging
	if ( DEBUG ) {
		warn "SpreadClient was stopped!";
	}

	# Wow, go disconnect ourself!
	$_[KERNEL]->call( $_[SESSION], 'disconnect' );

	return;
}

sub connect : State {
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
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'CONNECT', $@, $server, $priv );
		}

		# We're not connected...
		$_[HEAP]->{'DISCONNECTED'} = 1;
	} else {
		# Sanity
		if ( ! defined $mbox ) {
			# Inform our registered listeners
			foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
				$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'CONNECT', $sperrno, $server, $priv );
			}

			# We're not connected...
			$_[HEAP]->{'DISCONNECTED'} = 1;
		} else {
			# Debugging
			if ( DEBUG ) {
				warn "creating RW wheel for Spread";
			}

			# Set our data
			$_[HEAP]->{'SERVER'} = $server;
			$_[HEAP]->{'PRIV_NAME'} = $priv;
			$_[HEAP]->{'PRIV_GROUP'} = $priv_group;
			$_[HEAP]->{'MBOX'} = $mbox;

			# Create a FH to feed into Wheel::ReadWrite
			# we retry because... there seems to be several microseconds until fileno() works!
			# TODO we need to investigate the underlying cause of this...
			my $retries = 0;
			until ( ++$retries == 10 || ( $_[HEAP]->{'FH'} && fileno( $_[HEAP]->{'FH'} ) ) ) {
				open $_[HEAP]->{'FH'}, '<&=', $mbox;
				if ( DEBUG ) {
					warn "SpreadClient: bad fh!!! retrying" if ! fileno( $_[HEAP]->{'FH'} );
				}
			}
			if ( $retries == 10 ) {
				if ( DEBUG ) {
					warn "SpreadClient: UNABLE to create FH from mbox!";
				}

				# Inform our registered listeners
				foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
					$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'CONNECT', 'BADFH', $server, $priv );
				}

				# We're not connected...
				$_[HEAP]->{'DISCONNECTED'} = 1;
			} else {
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

				# We're connected...
				delete $_[HEAP]->{'DISCONNECTED'} if exists $_[HEAP]->{'DISCONNECTED'};
			}
		}
	}

	# All done!
	return;
}

sub disconnect : State {
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

	# Sanity
	if ( ! exists $_[HEAP]->{'DISCONNECTED'} ) {
		if ( DEBUG ) {
			warn "calling sp_disconnect";
		}

		# Set it in our heap that we've disconnected
		$_[HEAP]->{'DISCONNECTED'} = 1;

		# Inform our registered listeners
		# FIXME Should I use POST here instead?
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->call( $l, '_sp_disconnect', $_[HEAP]->{'PRIV_NAME'} );
		}
	}

	# All done!
	return;
}

sub destroy : State {
	# Okay, destroy ourself!
	$_[KERNEL]->call( $_[SESSION], 'disconnect' );

	# Get rid of our alias
	$_[KERNEL]->alias_remove( $_[HEAP]->{'ALIAS'} );

	# All done!
	return;
}

sub publish : State {
	my( $groups, $message, $mess_type, $flag ) = @_[ ARG0 .. ARG3 ];

	# Shortcut
	if ( ! defined $_[HEAP]->{'WHEEL'} ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'PUBLISH', CONNECTION_CLOSED, $groups, $message );
		}

		# All done!
		return;
	}

	# Sanity
	if ( ! defined $mess_type ) {
		$mess_type = 0;
	}

	# Spread.pm doesn't like one-member group via arrayref...
	if ( defined $groups ) {
		if ( ref $groups and ref( $groups ) eq 'ARRAY' and scalar @$groups == 1 ) {
			$groups = $groups->[0];
		}
	} else {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'PUBLISH', ILLEGAL_GROUP, undef, $message );
		}

		# All done!
		return;
	}

	# Send it!
	my $rtn;
	eval {
		# Should we do special flags?
		if ( defined $flag ) {
			$rtn = Spread::multicast( $_[HEAP]->{'MBOX'}, $flag, $groups, $mess_type, $message );
		} else {
			$rtn = Spread::multicast( $_[HEAP]->{'MBOX'}, SAFE_MESS, $groups, $mess_type, $message );
		}
	};
	if ( $@ or ! defined $rtn or $rtn < 0 ) {
		# Check for disconnect
		if ( defined $sperrno and $sperrno == CONNECTION_CLOSED ) {
			$_[KERNEL]->call( $_[SESSION], 'disconnect' );
		}

		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'PUBLISH', $sperrno, $groups, $message );
		}
	}

	# All done!
	return;
}

sub subscribe : State {
	# The groups to join
	my $groups = $_[ARG0];

	# Automatically add the sender session to listeners
	if ( ! exists $_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } ) {
		$_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } = 1;
	}

	# Shortcut
	if ( ! defined $_[HEAP]->{'WHEEL'} ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'SUBSCRIBE', CONNECTION_CLOSED, $groups );
		}

		# All done!
		return;
	}

	# sanity check
	if ( ! defined $groups ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'SUBSCRIBE', ILLEGAL_GROUP, undef );
		}

		# All done!
		return;
	}

	eval {
		# try to join each group
		foreach my $g ( ref $groups ? @$groups : $groups ) {
			if ( ! Spread::join( $_[HEAP]->{'MBOX'}, $g ) ) {
				# Check for disconnect
				if ( defined $sperrno and $sperrno == CONNECTION_CLOSED ) {
					die "disconnected";
				}

				# Inform our registered listeners
				foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
					$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'SUBSCRIBE', $sperrno, $g );
				}
			}
		}
	};
	if ( $@ ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'SUBSCRIBE', $sperrno, $groups );
		}

		if ( $@ eq "disconnected" ) {
			$_[KERNEL]->call( $_[SESSION], 'disconnect' );
		}
	}

	# All done!
	return;
}

sub unsubscribe : State {
	# The groups to unsub
	my $groups = $_[ARG0];

	# Shortcut
	if ( ! defined $_[HEAP]->{'WHEEL'} ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'UNSUBSCRIBE', CONNECTION_CLOSED, $groups );
		}

		# All done!
		return;
	}

	# sanity
	if ( ! defined $groups ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'UNSUBSCRIBE', ILLEGAL_GROUP, undef );
		}

		# All done!
		return;
	}

	eval {
		# try to leave each group
		foreach my $g ( ref $groups ? @$groups : $groups ) {
			if ( ! Spread::leave( $_[HEAP]->{'MBOX'}, $g ) ) {
				# Check for disconnect
				if ( defined $sperrno and $sperrno == CONNECTION_CLOSED ) {
					die "disconnected";
				}

				# Inform our registered listeners
				foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
					$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'UNSUBSCRIBE', $sperrno, $g );
				}
			}
		}
	};
	if ( $@ ) {
		# Inform our registered listeners
		foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
			$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'UNSUBSCRIBE', $sperrno, $groups );
		}

		if ( $@ eq "disconnected" ) {
			$_[KERNEL]->call( $_[SESSION], 'disconnect' );
		}
	}

	# All done!
	return;
}

# Registers interest in the client
sub register : State {
	# Automatically add the sender session to listeners
	if ( ! exists $_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } ) {
		$_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } = 1;
	}

	# All done!
	return;
}

# Unregisters interest in the client
sub unregister : State {
	# Automatically add the sender session to listeners
	if ( exists $_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID } ) {
		delete $_[HEAP]->{'LISTEN'}->{ $_[SENDER]->ID };
	}

	# All done!
	return;
}

sub RW_Error : State {
	# ARG0 = operation, ARG1 = error number, ARG2 = error string, ARG3 = wheel ID
	my ( $operation, $errnum, $errstr, $id ) = @_[ ARG0 .. ARG3 ];

	# Debugging
	if ( DEBUG ) {
		warn "ReadWrite wheel($id) got error $errnum - $errstr doing $operation";
	}

	# Disconnect now!
	$_[KERNEL]->call( $_[SESSION], 'disconnect' );

	return;
}

sub RW_GotPacket : State {
	# we might get multiple packets per read
	for my $packet ( @{ $_[ARG0] } ) {
		my( $type, $sender, $groups, $mess_type, $endian, $message ) = @$packet;

		# Check for disconnect
		if ( ! defined $type ) {
			# Disconnect now!
			$_[KERNEL]->call( $_[SESSION], 'disconnect' );
		} else {
			# Check the type
			if ( $type & REGULAR_MESS ) {
				# Do we have an endian problem?
				if ( defined $endian and $endian ) {
					# FIXME Argh!
					if ( DEBUG ) {
						warn "endian mis-match detected!";
					}
				}

				# Regular message
				foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
					$_[KERNEL]->post( $l, '_sp_message', $_[HEAP]->{'PRIV_NAME'}, $sender, $groups, $mess_type, $message );
				}
			} else {
				# Okay, figure out the type
				if ( $type &  TRANSITION_MESS ) {
					# Transitional Message
					foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
						$_[KERNEL]->post( $l, '_sp_admin', $_[HEAP]->{'PRIV_NAME'}, { 'TYPE' => 'TRANSITIONAL', 'GROUP' => $sender } );
					}
				} elsif ( $type & CAUSED_BY_LEAVE and ! ( $type & REG_MEMB_MESS ) ) {
					# Self leave
					foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
						$_[KERNEL]->post( $l, '_sp_admin', $_[HEAP]->{'PRIV_NAME'}, { 'TYPE' => 'SELF_LEAVE', 'GROUP' => $sender } );
					}
				} elsif ( $type & REG_MEMB_MESS ) {
					# Parse the message!
					my ( $gid1, $gid2, $gid3, $num_memb, $member );
					eval {
						( $gid1, $gid2, $gid3, $num_memb, $member ) = unpack( "IIIIa*", $message );
					};
					if ( $@ ) {
						# Inform our registered listeners
						foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
							$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'RECEIVE', $@ );
						}
					} else {
						# Okay, what was it?
						if ( $type & CAUSED_BY_JOIN ) {
							# Inform our registered listeners
							foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
								$_[KERNEL]->post( $l, '_sp_admin', $_[HEAP]->{'PRIV_NAME'}, { 'TYPE' => 'JOIN', 'GROUP' => $sender, 'MEMBERS' => $groups, 'WHO' => $member, 'GID' => [ $gid1, $gid2, $gid3 ], 'INDEX' => $mess_type } );
							}
						} elsif ( $type & CAUSED_BY_LEAVE ) {
							# Inform our registered listeners
							foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
								$_[KERNEL]->post( $l, '_sp_admin', $_[HEAP]->{'PRIV_NAME'}, { 'TYPE' => 'LEAVE', 'GROUP' => $sender, 'MEMBERS' => $groups, 'WHO' => $member, 'GID' => [ $gid1, $gid2, $gid3 ], 'INDEX' => $mess_type } );
							}
						} elsif ( $type & CAUSED_BY_DISCONNECT ) {
							# Inform our registered listeners
							foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
								$_[KERNEL]->post( $l, '_sp_admin', $_[HEAP]->{'PRIV_NAME'}, { 'TYPE' => 'DISCONNECT', 'GROUP' => $sender, 'MEMBERS' => $groups, 'WHO' => $member, 'GID' => [ $gid1, $gid2, $gid3 ], 'INDEX' => $mess_type } );
							}
						} elsif ( $type & CAUSED_BY_NETWORK ) {
							# FIXME Unpack the full nodelist
							#my @nodes = unpack( "a32" x ( length( $member ) / 32 + 1 ), $member );

							# Network failure
							foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
								$_[KERNEL]->post( $l, '_sp_admin', $_[HEAP]->{'PRIV_NAME'}, { 'TYPE' => 'NETWORK', 'GROUP' => $sender, 'MEMBERS' => $groups, 'GID' => [ $gid1, $gid2, $gid3 ], 'INDEX' => $mess_type, 'MESSAGE' => $message } );
							}
						} else {
							# Unknown?
							foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
								$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'RECEIVE', 'UNKNOWN PACKET TYPE' );
							}
						}
					}
				} else {
					# Unknown?
					foreach my $l ( keys %{ $_[HEAP]->{'LISTEN'} } ) {
						$_[KERNEL]->post( $l, '_sp_error', $_[HEAP]->{'PRIV_NAME'}, 'RECEIVE', 'UNKNOWN PACKET TYPE' );
					}
				}
			}
		}
	}

	# All done!
	return;
}

1;


__END__
=pod

=head1 NAME

POE::Component::SpreadClient - Handle Spread communications in POE

=head1 VERSION

  This document describes v1.001 of POE::Component::SpreadClient - released February 09, 2011 as part of POE-Component-SpreadClient.

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

This module should only be used with Spread 3.17.3 ( or compatible versions )

XXX Beware: this module hasn't been tested with Spread 4! XXX

=head1 METHODS

=head2 spawn

	POE::Component::Spread->spawn( 'spread' );

	- The alias the component will take ( default: "SpreadClient" )

	Returns the session ID.

=head1 Public API

=head2 connect

	$poe_kernel->post( spread => connect => '4444@localhost' );
	$poe_kernel->post( spread => connect => '4444@localhost', 'logger' );

	- The Server location
	- The private name for the Spread connection ( default: "spread-PID" )

	Connect this POE session to the Spread server on port 4444 on localhost.

	Will send a C<_sp_error> event if unable to connect; C<_sp_connect> if successful

=head2 disconnect

	$poe_kernel->post( spread => disconnect );

	Forces this session to disconnect. ( DOES NOT REMOVE ALIAS => look at destroy below )

	Will send a C<_sp_disconnect> event if disconnected; C<_sp_error> if failure

=head2 subscribe

	$poe_kernel->post( spread => subscribe => 'chatroom' );
	$poe_kernel->post( spread => subscribe => [ 'chatroom', 'testing' ] );

	- The group name(s)

	Subscribe to a Spread messaging group. Messages will be sent to C<_sp_message> and
	join/leave/etc to C<_sp_admin> in the registered listeners.

	Automatically adds the session to the registered listeners.

	Will send a C<_sp_error> if unable to subscribe; C<_sp_admin> with join message if successful

=head2 unsubscribe

	$poe_kernel->post( spread => unsubscribe => 'chatroom' );
	$poe_kernel->post( spread => unsubscribe => [ 'foobar', 'chatroom' ] );

	Unsubscribes to a Spread messaging group. Does not remove the session from the listener list.

	Will send a C<_sp_error> if unable to unsubscribe; C<_sp_admin> with self_leave if successful

=head2 publish

	$poe_kernel->post( spread => publish => 'chatroom', 'A/S/L?' );
	$poe_kernel->post( spread => publish => [ 'chatroom', 'stats' ], 'A/S/L?' );
	$poe_kernel->post( spread => publish => 'chatroom', 'special', 5 );
	$poe_kernel->post( spread => publish => 'chatroom', 'A/S/L?', undef, RELIABLE_MESS & SELF_DISCARD );

	- The group name(s)
	- 2nd parameter ( int ) is the Spread mess_type -> application-defined ( default: 0 )
	- The 3rd parameter is the spread message type -> import them from Spread.pm ( default: SAFE_MESS )

	Send a string to the group(s).

	THIS WILL ONLY SEND STRINGS! If you need to send perl structures, use your own serializer/deserializer!

	REMEMBER about the message size limitation

		From spread-src-3.17.3
		#define MAX_MESSAGE_BODY_LEN	(MAX_SCATTER_ELEMENTS * (MAX_PACKET_SIZE - 32)) /* 32 is sizeof(packet_header) */
		#define MAX_SCATTER_ELEMENTS    100
		#define MAX_PACKET_SIZE 1472	/*1472 = 1536-64 (of udp)*/

		Therefore max message size is 100 * 1440 =~ 140kB

	Will send a C<_sp_error> if unable to publish

=head2 register

	$poe_kernel->post( spread => register );

	Registers the current session as a "registered listener" and will receive all events.

=head2 unregister

	$poe_kernel->post( spread => unregister );

	Removes the current session from the "registered listeners" list.

=head2 destroy

	$poe_kernel->post( spread => destroy );

	Destroys the session by removing it's alias and disconnecting if needed with C<_sp_disconnect>

=head1 EVENTS

=head2 C<_sp_connect>

	sub _sp_connect : State {
		my( $priv_name, $priv_group ) = @_[ ARG0, ARG1 ];
		# We're connected!
	}

=head2 C<_sp_disconnect>

	sub _sp_disconnect : State {
		my $priv_name = $_[ ARG0 ];
		# We're disconnected!
	}

=head2 C<_sp_error>

	sub _sp_error : State {
		my( $priv_name, $type, $sperrno, $msg, $data ) = @_[ ARG0 .. ARG4 ];

		# Handle different kinds of errors
		if ( $type eq 'CONNECT' ) {
			# $sperrno = Spread errno/error string, $msg = server name, $data = priv name
		} elsif ( $type eq 'PUBLISH' ) {
			# $sperrno = Spread errno, $msg = $groups ( may be undef ), $data = $message ( may be undef )
		} elsif ( $type eq 'SUBSCRIBE' ) {
			# $sperrno = Spread errno, $msg = $groups ( may be undef )
		} elsif ( $type eq 'UNSUBSCRIBE' ) {
			# $sperrno = Spread errno, $msg = $groups ( may be undef )
		} elsif ( $type eq 'RECEIVE' ) {
			# $sperrno = error string
		}
	}

=head2 C<_sp_message>

	sub _sp_message : State {
		my( $priv_name, $sender, $groups, $mess_type, $message ) = @_[ ARG0 .. ARG4 ];

		# $mess_type is always 0 unless defined ( mess_type in Spread )
	}

=head2 C<_sp_admin>

	sub _sp_admin : State {
		my( $priv_name, $data ) = @_[ ARG0, ARG1 ];
		# $data is hashref with several fields:
		# TYPE => string ( JOIN | LEAVE | DISCONNECT | SELF_LEAVE | TRANSITIONAL | NETWORK )
		# GROUP => string ( group name )
		# GID => [ GID1, GID2, GID3 ] ( look at Spread documentation about this! )
		# MEMBERS => arrayref of member names
		# WHO => string ( whomever left/join/discon )
		# INDEX => index of self in group list
		# MESSAGE => raw unpacked message ( needed for NETWORK's special parsing, not done! )

		# if TYPE = JOIN | LEAVE | DISCONNECT
		# GROUP, MEMBERS, WHO, GID, INDEX

		# if TYPE = SELF_LEAVE
		# GROUP

		# if TYPE = TRANSITIONAL
		# GROUP

		# if TYPE = NETWORK
		# GROUP, MEMBERS, GID, INDEX, MESSAGE
	}

=head1 SpreadClient Notes

You can enable debugging mode by doing this:

	sub POE::Component::SpreadClient::DEBUG () { 1 }
	use POE::Component::SpreadClient;

=head1 SEE ALSO

Please see those modules/websites for more information related to this module.

=over 4

=item *

L<Spread>

=item *

L<Spread::Message>

=back

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders

=head1 SUPPORT

=head2 Perldoc

You can find documentation for this module with the perldoc command.

  perldoc POE::Component::SpreadClient

=head2 Websites

The following websites have more information about this module, and may be of help to you. As always,
in addition to those websites please use your favorite search engine to discover more resources.

=over 4

=item *

Search CPAN

L<http://search.cpan.org/dist/POE-Component-SpreadClient>

=item *

RT: CPAN's Bug Tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-SpreadClient>

=item *

AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/POE-Component-SpreadClient>

=item *

CPAN Ratings

L<http://cpanratings.perl.org/d/POE-Component-SpreadClient>

=item *

CPAN Forum

L<http://cpanforum.com/dist/POE-Component-SpreadClient>

=item *

CPANTS Kwalitee

L<http://cpants.perl.org/dist/overview/POE-Component-SpreadClient>

=item *

CPAN Testers Results

L<http://cpantesters.org/distro/P/POE-Component-SpreadClient.html>

=item *

CPAN Testers Matrix

L<http://matrix.cpantesters.org/?dist=POE-Component-SpreadClient>

=back

=head2 Email

You can email the author of this module at C<APOCAL at cpan.org> asking for help with any problems you have.

=head2 Internet Relay Chat

You can get live help by using IRC ( Internet Relay Chat ). If you don't know what IRC is,
please read this excellent guide: L<http://en.wikipedia.org/wiki/Internet_Relay_Chat>. Please
be courteous and patient when talking to us, as we might be busy or sleeping! You can join
those networks/channels and get help:

=over 4

=item *

irc.perl.org

You can connect to the server at 'irc.perl.org' and join this channel: #perl-help then talk to this person for help: Apocalypse.

=item *

irc.freenode.net

You can connect to the server at 'irc.freenode.net' and join this channel: #perl then talk to this person for help: Apocal.

=item *

irc.efnet.org

You can connect to the server at 'irc.efnet.org' and join this channel: #perl then talk to this person for help: Ap0cal.

=back

=head2 Bugs / Feature Requests

Please report any bugs or feature requests by email to C<bug-poe-component-spreadclient at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=POE-Component-SpreadClient>. You will be automatically notified of any
progress on the request by the system.

=head2 Source Code

The code is open to the world, and available for you to hack on. Please feel free to browse it and play
with it, or whatever. If you want to contribute patches, please send me a diff or prod me to pull
from your repository :)

L<http://github.com/apocalypse/perl-poe-spreadclient>

  git clone git://github.com/apocalypse/perl-poe-spreadclient.git

=head1 AUTHOR

Apocalypse <APOCAL@cpan.org>

=head1 ACKNOWLEDGEMENTS

The base for this module was lifted from POE::Component::Spread by
Rob Partington <perl-pcs@frottage.org>.

Thanks goes to Rob Bloodgood ( RDB ) for making sure this module still works!

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Apocalypse.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the LICENSE file included with this distribution.

=cut

