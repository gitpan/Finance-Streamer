#!/usr/bin/perl -w
use strict;
use lib '../lib';

#
# This is the example in the SYNOPSIS of the Finance::Streamer documentation.
#

use Finance::Streamer;

my $user = 'USER1234';
my $pass = 'SF983JFDLKJSDFJL8342398KLSJF8329483LF';
my $symbols = 'JDSU+QCOM+AMAT+IBM';
my $select = '0+1+2+3+4+8+9+21';

my $streamer = Finance::Streamer->new( user => $user,
					pass => $pass,
					symbols => $symbols,
					'select' => $select,
					);

my $sub = sub
{
	my (%all_data) = @_;

	foreach my $symbol (keys %all_data) {
		print "$symbol\n";
		my %data = %{$all_data{$symbol}};
		foreach my $data_part (keys %data) {
			print "\t$data_part","=",$data{$data_part},"\n";
		}
	}
};

$streamer->{'sub'} = $sub;

$streamer->receive;
