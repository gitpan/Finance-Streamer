#
# If you don't know what the '{{{' '}}}' are for, they are used
#  for folds in the vim text editor (:help fold).
#

# {{{ Intro

=head1 NAME

Finance::Streamer - Interface to Datek Streamer.

=head1 VERSION

This document refers to version 1.07 of Finance::Streamer,
released Tue, 27 Aug 2002.

=head1 SYNOPSIS

 use Finance::Streamer;

 my $user = 'USER1234';
 my $pass = 'SF983JFDLKJSDFJL8342398KLSJF8329483LF';
 my $symbols = 'JDSU+QCOM+AMAT+IBM+^COMPX';
 my $fields = '0+1+2+3+4+8+9+21';

 my $streamer = Finance::Streamer->new( user => $user,
					pass => $pass,
					symbols => $symbols,
					fields => $fields,
					);

 my $sub = sub
 {
	my (%all_data) = @_;

	foreach my $symbol (keys %all_data) {
		print "$symbol\n";
		my %data = %{$all_data{$symbol}};
		foreach my $data_part (keys %data) {
			print "$data_part", "=", $data{$data_part}, "\n";
		}
	}
 };

 $streamer->{sub_recv} = $sub;

 #$streamer->receive;
 $streamer->receive_all;

=head1 DESCRIPTION

This library provides an interface that can be used to access 
Datek Streamer market data.

It works with the new Streamer (version 3) as opposed to the older (version 2).

There are four subroutines available to use.  The first two, I<connect> and 
I<Parser>, make the required tasks of connecting to a Streamer server and
parsing raw quote data into an easier to use format (such as a hash) easy 
to do.  The third, I<receive>, makes the task of using the data as easy as 
possible by using the previously mentioned subroutines (connect, receive).
The fourth, I<receive_all>, is identical to I<receive> but it returns
the data state.

If you just want to use the data, focus on the functions 
I<receive> and I<receive_all>.  If you want to know how the protocol
works (roughly), focus on the I<connect> and I<Parser> functions.

=cut

# }}}

package Finance::Streamer;
use strict;
use warnings;

use Carp;

our $VERSION = 1.08;

use IO::Socket::INET;
use IO::Select;

use constant TRUE => 1;
use constant FALSE => 0;

# Default id used for connect() if nothing else is specified.
my $USER_AGENT = __PACKAGE__ . "/$VERSION ".
		"http://www.cpan.org/authors/id/J/JE/JERI";
# "name of agent/version" "link to find more info"

# status codes
my $QUOTE_RECV = 83;
my $AUTH_FAILED = 68;
my $HEARTBEAT = 72;

my $SERVER = 'streamerapp.datek.com';
my $PORT = 80;

# max size of buffer used for recv()
my $RECV_MAX = 3000;

# default timeout in seconds of socket
# Used for connect(), recv().
my $TIMEOUT = 60;	

=head1 OPERATIONS

=cut

# {{{ new

=head2 Finance::Streamer->new;

	Returns: defined object on success, FALSE otherwise

The I<new> sub stores the values passed to it for use by other
subroutines later.  For example, if you wanted to use a
subroutine that required a value for I<symbols> to be defined,
you could do it like so.

 $obj = Finance::Streamer->new(symbols => $your_symbols)
 	or die "error new()";

 # then use the sub that requires "symbols"

=cut

sub new
{
	my ($class, %args) = @_;

	bless { %args
		}, $class;
}
# }}}

# {{{ connect

=head2 $obj->connect;

	Returns: IO::Socket::INET object on success, FALSE on error

	Requires the following object attributes:
		user pass symbols fields [agent] [timeout]

The I<connect> sub is used to initiate a connection with the data server.

The object attributes I<user>, I<pass>, I<symbols>, I<fields>, 
optional I<agent>, and an optional I<timeout>, 
must be defined in the I<streamer> object
before using this subroutine.
Each is describe in more detail below.

 $obj->{user} = $user;
 $obj->{pass} = $pass;
 $obj->{symbols} = $symbols;
 $obj->{fields} = $fields;
 $obj->{agent} => $agent;	# optional
 $obj->{timeout} => $timeout;	# optional

The I<user> and I<pass> value is the user name and password of the account
to be used for receiving data.  See the section 
"how to obtain user name and password" below, for more info.  

B<IMPORTANT> - If the I<user> or I<pass> is wrong, there is no 
indication other than no data arriving after connection.

The I<symbols> value can contain up to 23 symbols in all uppercase joined by
a '+' character.

 $symbols = "JDSU+QCOM+AMAT+IBM";

The I<fields> value can be any combination of the integers 0 to 21 in
sequential order joined by the '+' character.  See the section 
"field numbers" below, for more info.

 $fields = "0+1+2+3+21";

The I<agent> field determines the id of this library when it connects to
a Streamer server.  By default the id is the name of this library.  The
string should be one line with B<no> carriage return ('\n').

 $agent = "My Server 1.01";

The I<timeout> specifies the maximum number of seconds to wait for the
connection to succeed.  The default value of B<60 seconds> is used
if no value is specified.

 $timeout = 30;

 my $sock = $obj->connect
 	or die "error connect()";

=cut

sub connect
{
	my ($self) = @_;

	my ($user, $pass) = ($self->{user}, $self->{pass});
	my $symbols = $self->{symbols};
	my $fields = $self->{fields};
	my $timeout = $self->{timeout} || $TIMEOUT;
		# 0 will go to default

	my $agent = $self->{agent} || $USER_AGENT;

	my $sock = IO::Socket::INET->new(PeerAddr => $SERVER,
					 PeerPort => $PORT,
					 Proto	  => 'tcp',
					 Timeout  => $timeout,
					 );
	unless($sock) {
		my $time = localtime(time);
		print STDERR "$time: connect(), socket creation failed: $!\n";
		return undef;
	}

	# message used for request
	my $msg = "GET /!U=$user&W=$pass|S=QUOTE&C=SUBS&P=$symbols".
		"&T=$fields".
		" HTTP/1.1\n".		# DO NOT FORGET SPACE BEFORE (' HT...')
		"Accept-Language: en\n".
		"Connection: Keep-Alive\n".
#		"User-agent: Streamer Display v1.9.9.3\n".
		"User-agent: $agent\n".
#		"Accept: text/html, image/gif, image/jpeg, ".
#		"*; q=.2, */*; q=.2\n".
		"Host: $SERVER\n\n";
	# Must have CR('\n') or it won't work.
	# This is the exact message that was observed while "sniffing"
	#  the packets of the Streamer when it was initiating a connection.
	#  This can be left un-changed so that the servers providing data
	#  have no way of differentiating this from the Streamer application 
	#  provided by Datek.
	#  This message is current as of Tue May 22 21:23:59 PDT 2001

	unless ($sock->send($msg, 0)) {
		my $time = localtime(time);
		print STDERR "$time: connect(), initial send() failed: $!\n";
		return undef;
	}

	{
	my $buf;
	$sock->recv($buf, 512);
	unless ($buf) {
		my $time = localtime(time);
		print STDERR "$time: connect(), initial recv() failed: $!\n";
		return undef;
	}
	}

	return $sock;
}
# }}}

# {{{ Parser

=head2 Finance::Streamer::Parser($raw_data);

	Returns: %data on success, FALSE otherwise

The I<Parser> subroutine changes raw quote data into a form that
is easier to use.

B<IMPORTANT> - The raw quote data must have been received using 
the I<fields> value 0 or this subroutine wont work.

This subroutine does not use the I<streamer> object, so the name must
be fully specified.  The only argument that is required is a variable 
containing the raw data for a quote.

If the parser is successful a hash containing the data will be returned.  
The hash will contain a key for each symbol that data was received for.  
Each symbol entry is a reference to another hash that has a key for 
each value that data is available for.  A helpful tool for visualizing this
is the I<Data::Dumper> module.

Many checks/tests are made while the data is being parsed.  If something 
is wrong with the data, an error message will be printed to STDERR 
and I<undef> will be returned if the error was substantial enough that
the quote data is wrong.

=cut

# update notification
sub filter { carp "Your code needs to be updated\n".
		"rename the function filter() to Parser()\n";
		&Parser };

sub Parser
{
	my ($raw_data) = @_;

	my %symbols;	# storage for data of all symbols

	my $tot_bytes = length($raw_data);

	my $i;		# index of 'for' loop and check at end
	for ($i = 0; $i < $tot_bytes;) {
		my %sym;		# storage for data of 1 symbol

		$i += 1;		# status

		my $size = unpack("x$i n", $raw_data);
		$i += 2;		# size of data segment

		# check to make sure enough room is left
		my $p = $i + $size;
		if ($p > $tot_bytes) {
			print STDERR "Parser(), ".
				"There should be more data, ".
				"quote buffer is corrupt\n".
				"\tamount needed: $p\n".
				"\tamount left: $tot_bytes\n".
				"aborting quote processing\n";
			return undef;
		}

		my $one = unpack("x$i n", $raw_data);
		if ($one != 1) {
			print STDERR "Parser(), ".
				"This value should alway equal 1, ".
				"but the actual value is '$one'.".
				"The quote buffer may be corrupt, ".
				"but I am continuing anyway\n";
		}

		$i += 2;	# "one"

		$i++;		# symbol length starts ahead 1 byte
		my $sym_len = unpack("x$i n", $raw_data);
		$i += 2;	# symbol length

		$sym{symbol} = unpack("x$i a$sym_len", $raw_data);
		$i += $sym_len;	# symbol characters

		# for every piece of data for 1 symbol
		for (;$i < $p;) {
			my $id = unpack("x$i C", $raw_data);	
			$i++;		# id

			if ($id == 1) {
				my $v = unpack("x$i B32", $raw_data);
				my $bid = _bin2float($v);
				$sym{bid} = $bid;
				$i += 4;
			} elsif ($id == 2) {
				my $v = unpack("x$i B32", $raw_data);
				my $f = _bin2float($v);
				$sym{ask} = $f;
				$i += 4;
			} elsif ($id == 3) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{'last'} = _bin2float($x);
				$i += 4;
			} elsif ($id == 4) {
				my $x = unpack("x$i N", $raw_data);
				$sym{bid_size} = $x;
				$i += 4;
			} elsif ($id == 5) {
				my $x = unpack("x$i N", $raw_data);
				$sym{ask_size} = $x;
				$i += 4;
			} elsif ($id == 6) {
				my $v = unpack("x$i n", $raw_data);
				$sym{bidID} = chr $v;
				$i += 2;
			} elsif ($id == 7) {
				my $v = unpack("x$i n", $raw_data);
				$sym{askID} = chr $v;
				$i += 2;
			} elsif ($id == 8) {
				$i += 4;
				my $v = unpack("x$i N", $raw_data);
				$sym{volume} = $v;
				$i += 4;
			} elsif ($id == 9) {
				my $v = unpack("x$i N", $raw_data);
				$sym{last_size} = $v;
				$i += 4;
			} elsif ($id == 10) {
				my $v = unpack("x$i N", $raw_data);

				my ($s, $m, $h) = gmtime($v);
				# The time data received is in gmt and only
				#  provides hour, minute, sec.

				$h = "0$h" if ($h <= 9);
				$m = "0$m" if ($m <= 9);
				$s = "0$s" if ($s <= 9);
				$sym{trade_time} = "$h:$m:$s";
				$i += 4;
			} elsif ($id == 11) {
				my $v = unpack("x$i N", $raw_data);
				my ($s, $m, $h) = gmtime($v);
				$h = "0$h" if ($h <= 9);
				$m = "0$m" if ($m <= 9);
				$s = "0$s" if ($s <= 9);
				$sym{quote_time} = "$h:$m:$s";
				$i += 4;
			} elsif ($id == 12) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{high} = _bin2float($x);
				$i += 4;
			} elsif ($id == 13) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{low} = _bin2float($x);
				$i += 4;
			} elsif ($id == 14) {
				my $x = unpack("x$i n", $raw_data);
				$sym{BT} = chr $x;
				$i += 2;
			} elsif ($id == 15) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{prev_close} = _bin2float($x);
				$i += 4;
			} elsif ($id == 16) {
				my $x = unpack("x$i n", $raw_data);
				$sym{exch} = chr $x;
				$i += 2;
			} elsif ($id == 17) {
				# what is this?
			} elsif ($id == 18) {
				# what is this?
			} elsif ($id == 19) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{isld_bid} = _bin2float($x);
				$i += 4;
			} elsif ($id == 20) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{isld_ask} = _bin2float($x);
				$i += 4;
			} elsif ($id == 21) {
				$i += 4;
				my $v = unpack("x$i N", $raw_data);
				$sym{isld_vol} = $v;
				$i += 4;
			} else {
				print STDERR "fields id of '$id' ".
					"is not available, aborting\n";
				return undef;
			}
		}
		if ($i != $p) {
			print STDERR "Parser(), parity check wrong: $i != $p\n";
			return undef;
		}

		my $term = unpack("x$i n", $raw_data);
		if ($term != 65290) {
			print STDERR "Parser(), terminator wrong: $term\n";
			return undef;
		}
		$i += 2;	# terminator

		$symbols{$sym{symbol}} = \%sym;
	}

	if ($i != $tot_bytes) {
		print STDERR "Parser(), ".
			"quote processing error: $i != $tot_bytes\n";
		return undef;
	}

	return %symbols;
}
# }}}

# {{{ receive

=head2 $obj->receive;

	Returns: does not return

	Requires the following object attributes:
 		sub_recv user pass symbols fields [timeout] [sub_hrtbt]

The I<receive> subroutine deals with all the issues of connecting to the
server, receiving data, etc, and executes the subroutine specified by 
I<sub_recv>, passing a single argument which contains the quote data 
every time a quote is received.  

The object attributes I<sub_recv>, I<user>, I<pass>, I<symbols>, I<fields>,
optional I<timeout> and optional I<sub_hrtbt> must be defined
before using this subroutine.

 $obj->{sub_recv} = $sub_ref;
 $obj->{sub_hrtbt} = $sub_ref_heartbeat;

The I<sub_recv> value is a reference to a subroutine to be executed
when new quote data arrives.  One argument, an object of parsed
data as returned by I<Parser>, will be passed to this subroutine.

The values I<user>, I<pass>, I<symbols>, I<fields> and I<timeout> are used 
for the I<connect> subroutine.  See the section on I<connect> for more 
information.

The I<timeout> value, while it is used for I<connect>, is also used in 
this subroutine to specify the maximum number of seconds to wait for 
new data to arrive before reconnecting.  The default value of B<60 seconds> 
is used if no value is specified.

The I<sub_hrtbt> value is a reference to a subroutine to be executed
when a B<heartbeat> happens.  One argument, the time at which the heartbeat
occurred, will be passed to this subroutine when executed.

Error messages may be displayed.  Messages about errors receiving data 
will indicate why and may result in a reconnection.  Messages about
the status indicated in the received data are for information purposes 
and do not usually result in a reconnect.  All messages are displayed
to STDERR and so can be easily redirected.  An example of how to turn off
messages is below, where "a.out" is the name of the program and "2" is the
number of the file descriptor representing standard error.

 a.out 2>/dev/null

=cut

sub receive
{
	my ($self) = @_;
	my $sub = $self->{sub_recv};
	my $hb_sub = $self->{sub_hrtbt};
	my $timeout = $self->{timeout} || $TIMEOUT;

	while(1) {
		my $sock = $self->connect;
		if ($sock) {
			my $time = localtime(time);
			print STDERR "$time: receive(), connect() OK\n";
		} else {
			my $time = localtime(time);
			print STDERR "$time: receive(), connect() failed: $!\n";
			next;
		}

		my $sel = IO::Select->new;
		$sel->add($sock);

		# receive data forever
		while(1) {
			my $buf;

			if ($sel->can_read($timeout)) {
				$sock->recv($buf, $RECV_MAX);
			} else {
				my $time = localtime(time);
				print STDERR "$time: receive(), timeout #1\n";
				last;
			}

			unless ($buf) {
				my $time = localtime(time);
				print STDERR "$time: receive(), err #1\n";
				last;
			}

			my $status = unpack("C", $buf);
			if ($status == $QUOTE_RECV) {
				my $err;

				# get all data of quote
				while(1) {
					my $len = length($buf);
					my $j = $len - 2;
					my $ter = unpack("x$j n", $buf);
					last if ($ter == 65290);

					my $t_buf;

					if ($sel->can_read($timeout)) {
						$sock->recv($t_buf, $RECV_MAX);
					} else {
						$err = 1;
						my $time = localtime(time);
						print STDERR "$time: ".
							"receive(), ".
							"timeout #2\n";
						last;
					}

					unless ($t_buf) {
						$err = 1;
						my $time = localtime(time);
						print STDERR "$time: ".
							"receive(), ".
							"err #2\n";
						last;
					}

					$buf .= $t_buf;
				}

				# abort if error, otherwise pass data to sub
				last if ($err);

				{ # parse data and send to specified sub
				my %data = Parser($buf);
				$sub->(%data);
				}
			} elsif ($status == $HEARTBEAT) {
				my $time = localtime(time);
#print STDERR "$time: receive(), heartbeat\n";
				$hb_sub->($time) if (defined $hb_sub);
				next;
			} else {
				my $time = localtime(time);
				print STDERR "$time: receive(), ".
					"unknown status\n";
				# This is a common result
			}
		}
		close($sock);
	}
}
# }}}

# {{{ receive_all

=head2 $obj->receive_all;

Identical to the function receive() except that instead of getting just the
changed values, any values that do not have changed values have their most
recent value.  So, it sort of keeps a current state changing only the
values that are updated returning the current state.

 Example:
 1: bid_size = 200, ask_size = 300
 2: bid_size = 400			# receive()
 2: bind_size = 400, ask_size = 300	# receive_all()

=cut

sub receive_all
{
	my ($self) = @_;

	my $orig_sub = $self->{sub_recv};

	my %cur_data;

	my $sub = sub {
		my (%new_data) = @_;

		my %new_all;
		foreach my $symbol (keys %new_data) {
			if (defined $cur_data{$symbol}) {
				my %values = %{$new_data{$symbol}};
				foreach my $val_name (keys %values) {
					$cur_data{$symbol}{$val_name} =
							$values{$val_name};
				}
				$new_all{$symbol} = $cur_data{$symbol};
			} else {
				$cur_data{$symbol} = $new_data{$symbol};
				$new_all{$symbol} = $cur_data{$symbol};
			}
#my $len_vals = keys %{$new_all{$symbol}};
#print STDERR "Lib: $symbol, $len_vals\n";
		}

		$orig_sub->(%new_all);
	};

	$self->{sub_recv} = $sub;	# replace

	$self->receive;
}
# }}}

# {{{ local subroutines DO NOT USE OUTSIDE THIS MODULE

sub _bin2float
{
	my ($bin) = @_;

	my ($sign, $exp, $mant);

	my @bin = unpack("C*", $bin);

	if (@bin != 32) {
		my $l = @bin;
		print STDERR "_bin2float requires 32 bit value, not $l\n";
		return undef;
	}

	if ($bin[0] eq ord('1')) {
		$sign = -1;
	} elsif ($bin[0] eq ord('0')) {
		$sign = 1;
	}

	my @exp = @bin[1..8];
	$exp = pack("C*", @exp);
	$exp = _bin2int($exp) - 127;

	my @mant = @bin[9..31];
	$mant = pack("C*", @mant);
	$mant = _bin2mant($mant);

	my $float = $sign * ($mant * (2 ** $exp));

	return $float;
}

# binary to mantissa
#
# The mantissa of a floating point number has its own
# peculiar way of being stored.
#
sub _bin2mant
{
	my ($bin) = @_;

	my @chars = unpack("C*", $bin);
	my $int = 1;

#	@chars = reverse @chars;
	for (my $i = 0; $i < @chars; $i++) {
		if ($chars[$i] eq ord('1')) {
			$int  += 2 ** (($i+1) * -1);
		}
	}

	return $int;
}

sub _bin2int
{
	my ($bin) = @_;

	my @chars = unpack("C*", $bin);
	my $int = 0;

	@chars = reverse @chars;
	for (my $i = 0; $i < @chars; $i++) {
		if ($chars[$i] eq ord('1')) {
			$int  += 2**$i;
		}
	}

	return $int;
}
# }}}

1;

=head1 NEED TO KNOW

This section contains information that must be understood in order to use this
library.

=head2 how to obtain user name and password

When you first start the Streamer application provided by Datek a window
will pop up giving you a choice of what you want to launch 
(Streamer, Portfolio, Last Sale, Index).  If you look at the html source of
that window you will find near the top a place where your user name
is displayed in all capitals (e.g. "USER12345") and below it is
a long string of upper case letters and numbers.  The long string is your
password.

=head2 field numbers

The I<field numbers> are used to choose what data you want to receive for
each symbol.

 number		name		description
 ------		----		-----------
 0		symbol
 1		bid
 2		ask
 3		last
 4		bid_size	size of bid in 100's
 5		ask_size	size of ask in 100's
 6		bidID		(Q=Nasdaq)
 7		askID
 8		volume		total volume
 9		last_size	size of last trade
 10		trade_time	time of last trade (HH:MM:SS)
 11		quote_time	time of last quote (HH:MM:SS)
 12		high		high of day
 13		low		low of day
 14		BT		tick, up(U) or down(D)
 15		prev_close	previous close
 16		exch		exchange(q=Nasdaq)
 17		?		do not use, unknown
 18		?		do not use, unknown
 19		isld_bid	Island bid
 20		isld_ask	Island ask
 21		isld_vol	Island volume

=head1 PREREQUISITES

 Module             Version
 ------             -------
 IO::Socket::INET   1.25
 IO::Select         1.14

=head1 AUTHOR

Jeremiah Mahler E<lt>jmahler@pacbell.netE<gt>

=head1 COPYRIGHT

Copyright (c) 2002, Jeremiah Mahler. All Rights Reserved.
This module is free software.  It may be used, redistributed
and/or modified under the same terms as Perl itself.

=cut

# vi:foldmethod=marker
