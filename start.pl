#!/usr/bin/env perl

our $VERSION = 0.1;

# use v5.20.0;

use utf8;
use strict;
use warnings;
use feature qw/say switch unicode_strings/;

use Coro;
use JSON::XS;
use File::Slurp;
use Coro::Select;
use LWP::UserAgent;

use constant DEBUG => 0;
use constant DEBUGWWW => 0;

# Read config
my $config;
eval { $config = decode_json(read_file('config.json')); };
if ($@) { say '[!] Can\'t read config file! ERROR: '.$@; exit; }

# Read services list
my $services;
eval { $services = decode_json(read_file('services.json')); };
if ($@) { say '[!] Can\'t read services list file! ERROR: '.$@; exit; }

# Open input file
open(INPUT, '<', $config->{input}) or die "Can't open input file! File[".$config->{input}."] Error[".$!."]";

my @coros;
for (1..$config->{threads}) {
	push @coros, async {
		my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0 (X11; U; Linux i686; cs-CZ; rv:1.7.12) Gecko/20050929' );
		$ua->max_redirect(5);

		$ua->proxy(['http', 'https'] => 'http://localhost:8888') if (DEBUGWWW);

		while (my $hash = <INPUT>) {
			next unless (defined $hash);
			chomp($hash);

			for my $service (@{$services}) {
				unless ($hash =~ m#$service->{inputFilter}#) {
					say '[!] Filtred hash! Service['.$service->{service}.' ('.$service->{hashType}.') ] Hash['.$hash.'] Filter['.$service->{inputFilter}.']'
						if (DEBUG);
					next;
				}

				my ($targetURL, $content, $method) = (
					$service->{request}->{uri},
					$service->{request}->{data},
					$service->{request}->{method}
				);

				my %DATA_ = %{$service->{request}->{data}};
				$service->{request}->{data} = \%DATA_;

				if ($method eq 'GET') {
					$targetURL =~ s/\{HASH\}/$hash/g;

					my $result = $ua->get($targetURL);
					my ($password) = $result->as_string =~ $service->{responsRegexp}; 

					if (defined $password) {
						say '[+] Service['.$service->{service}.' ('.$service->{hashType}.') ]'."\t".$hash.':'.$password;
						say 'DBG:'."\n".$result->as_string."\n" if (DEBUG);
						append_file( $config->{output}, $hash.':'.$password."\t(".$service->{hashType}.")\n" ) ;
						last;
					} else {
						say '[-] Service['.$service->{service}.' ('.$service->{hashType}.') ]'."\t".$hash  if (DEBUGWWW);
						say 'DBG:'."\n".$result->as_string."\n" if (DEBUG);
					}

				} elsif ($method eq 'POST') {
					$targetURL =~ s/\{HASH\}/$hash/g;
					$content->{$_} =~ s/\{HASH\}/$hash/g for (keys %{$content});

					my $result = $ua->post($targetURL, $content);
					my ($password) = $result->as_string =~ $service->{responsRegexp}; 

					if (defined $password) {
						say '[+] Service['.$service->{service}.' ('.$service->{hashType}.') ]'."\t".$hash.':'.$password;
						say 'DBG:'."\n".$result->as_string."\n" if (DEBUG);
						append_file( $config->{output}, $hash.':'.$password."\t(".$service->{hashType}.")\n" ) ;
						last;
					} else {
						say '[-] Service['.$service->{service}.' ('.$service->{hashType}.') ]'."\t".$hash  if (DEBUGWWW);
						say 'DBG:'."\n".$result->as_string."\n" if (DEBUG);
					}

				} else {
					say '[!] Undefined request method Method['.$service->{request}->{method}.'] Service['.$service->{service}.' ('.$service->{hashType}.') ]';
					next;
				}
			}
		}
	}
}

$_->join for (@coros);

close(INPUT);