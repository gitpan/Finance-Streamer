package Finance::Streamer;

require 5.005_62;
use strict;
use warnings;

our $VERSION = '1.03';

use IO::Socket::INET 1.25;
use IO::Select 1.14;

# status codes
my $QUOTE_RECV = 83;
my $AUTH_FAILED = 68;
my $HEARTBEAT = 72;

my $SERVER = 'streamerapp.datek.com';
my $PORT = 80;

# max size of buffer used for recv()
my $RECV_MAX = 3000;

# max length of a symbol in chars/bytes
my $MAX_SYM_LEN = 5;

# defaul timeout in seconds of socket
# Used for connect(), recv().
my $TIMEOUT = 60;	

sub new
{
	my ($pkg, %arg) = @_;

	bless { %arg
		}, $pkg;
}
# The "new" sub's main purpose is to store the varibles that will be needed by
#  other subroutines.

#
# The connect sub is used to establish a connection with the data server.
#  If it is successful, a socket will be returned that can be used to recieve
#  data, otherwise "undef" will be returned.
#
sub connect
{
	my ($self) = @_;

	my ($user, $pass) = ($self->{user}, $self->{pass});
	my $symbols = $self->{symbols};
	my $select = $self->{'select'};
	my $timeout = $self->{timeout} || $TIMEOUT;

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
		"&T=$select".
		" HTTP/1.1\n".		# DO NOT FORGET SPACE(' HT...')
		"Accept-Language: en\n".
		"Connection: Keep-Alive\n".
		"User-agent: Streamer Display v1.9.9.3\n".
		"Accept: text/html, image/gif, image/jpeg, ".
		"*; q=.2, */*; q=.2\n".
		"Host: $SERVER\n\n";
	# Must have CR('\n') or it wont work.
	# This is the exact message that was observed while "sniffing"
	#  the packets of the Streamer when it was initiating a connection.
	#  This should be left un-changed so that the servers providing data
	#  have no way of differentiating this from the Streamer application 
	#  provided by Datek.
	#  This message is current as of Sun Apr  8 00:54:10 PDT 2001.

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
# The main things that are needed to connect are the "user", "pass", 
#  "symbols" and "select".  The "symbols" can be from 1 to 23 symbols in all
#  uppercase joined by '+'.  The "select" can be any number from 0 to 21
#  in ascending sequence joined by '+'.

#
# The filter sub filter's a buffer of raw quote data into a meaningful
# format.
#
sub filter
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
			print STDERR "filter(), ".
				"There should be more data, ".
				"quote buffer is corrupt\n".
				"\tamount needed: $p\n".
				"\tamount left: $tot_bytes\n".
				"aborting quote processing\n";
			return undef;
		}

		my $one = unpack("x$i n", $raw_data);
		if ($one != 1) {
			print STDERR "filter(), ".
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

		if ($sym_len > $MAX_SYM_LEN) {
			print STDERR "filter(), ".
				"symbol length of '$sym_len' ".
				"is to big, aborting quote processing\n";
			return undef;
		}

		# for every piece of data for 1 symbol
		for (;$i < $p;) {
			my $id = unpack("x$i C", $raw_data);	
			$i++;		# id

			if ($id == 1) {
				my $v = unpack("x$i B32", $raw_data);
				my $bid = bin2float($v);
				$sym{bid} = $bid;
				$i += 4;
			} elsif ($id == 2) {
				my $v = unpack("x$i B32", $raw_data);
				my $f = bin2float($v);
				$sym{ask} = $f;
				$i += 4;
			} elsif ($id == 3) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{'last'} = bin2float($x);
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
				# The time data recieved is in gmt and only
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
				$sym{high} = bin2float($x);
				$i += 4;
			} elsif ($id == 13) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{low} = bin2float($x);
				$i += 4;
			} elsif ($id == 14) {
				my $x = unpack("x$i n", $raw_data);
				$sym{BT} = chr $x;
				$i += 2;
			} elsif ($id == 15) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{prev_close} = bin2float($x);
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
				$sym{isld_bid} = bin2float($x);
				$i += 4;
			} elsif ($id == 20) {
				my $x = unpack("x$i B32", $raw_data);
				$sym{isld_ask} = bin2float($x);
				$i += 4;
			} elsif ($id == 21) {
				$i += 4;
				my $v = unpack("x$i N", $raw_data);
				$sym{isld_vol} = $v;
				$i += 4;
			} else {
				print STDERR "select id of '$id' ".
					"is not available, aborting\n";
				return undef;
			}
		}
		if ($i != $p) {
			print STDERR "filter(), parity check wrong: $i != $p\n";
			return undef;
		}

		my $term = unpack("x$i n", $raw_data);
		if ($term != 65290) {
			print STDERR "filter(), terminator wrong: $term\n";
			return undef;
		}
		$i += 2;	# terminator

		$symbols{$sym{symbol}} = \%sym;
	}

	if ($i != $tot_bytes) {
		print STDERR "filter(), ".
			"quote proccessing error: $i != $tot_bytes\n";
		return undef;
	}

	return %symbols;
}

sub receive
{
	my ($self) = @_;
	my $sub = $self->{'sub'};
	my $filter = $self->{filter};
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

		my $sel = IO::Select->new();
		$sel->add($sock);

		# recieve data forever
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

				# determine whether to "filter" or not
				if (defined $filter and $filter == -1) {
					$sub->($buf);
				} else {
					my %data = filter($buf);
					$sub->(%data);
				}
			} elsif ($status == $HEARTBEAT) {
				my $time = localtime(time);
				print STDERR "$time: receive(), heartbeat\n";
				next;
			} else {
				my $time = localtime(time);
				print STDERR "$time: receive(), ".
					"unknown status\n";
				# This is a common occurance
			}
		}
		close($sock);
	}
}


#***> local subroutines - do no use ouside this module! <***********************

sub bin2float
{
	my ($bin) = @_;

	my ($sign, $exp, $mant);

	my @bin = unpack("C*", $bin);

	if (@bin != 32) {
		my $l = @bin;
		print STDERR "bin2float requires 32 bit value, not $l\n";
		return undef;
	}

	if ($bin[0] eq ord('1')) {
		$sign = -1;
	} elsif ($bin[0] eq ord('0')) {
		$sign = 1;
	}

	my @exp = @bin[1..8];
	$exp = pack("C*", @exp);
	$exp = bin2int($exp) - 127;

	my @mant = @bin[9..31];
	$mant = pack("C*", @mant);
	$mant = bin2mant($mant);

	my $float = $sign * ($mant * (2 ** $exp));

	return $float;
}

# binary to mantissa
#
# The mantissa of a floating point number has its own
# peculiar way of being stored.
#
sub bin2mant
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

sub bin2int
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

1;
