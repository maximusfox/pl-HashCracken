#!/usr/bin/env perl

our $VERSION = 0.2;

use utf8;
use strict;
use warnings;
use feature qw/say switch unicode_strings/;

use Coro;
use JSON::XS;
use File::Slurp;
use Coro::Select;
use Getopt::Args;
use LWP::UserAgent;
use Term::ANSIColor qw(:constants);

opt help => (
	isa     => 'Bool',
	alias   => 'h',
	default => 0,
	comment => 'Show help message',
);

opt header => (
	isa     => 'Str',
	alias   => 'hd',
	default => 'on',
	comment => 'Show or not header information [on|off] (default on)',
);

opt in => (
	isa     => 'Str',
	alias   => 'i',
	default => 'input.txt',
	comment => 'Input file (default input.txt)',
);
 
opt good => (
	isa     => 'Str',
	alias   => 'g',
	default => 'good.txt',
	comment => 'Good output file (default good.txt)',
);

opt bad => (
	isa     => 'Str',
	alias   => 'b',
	default => 'bad.txt',
	comment => 'Bad output file (default bad.txt)',
);

opt config => (
	isa     => 'Str',
	alias   => 'C',
	default => 'config.json',
	comment => 'JSON config file (default config.json)',
);

opt services => (
	isa     => 'Str',
	alias   => 'S',
	default => 'services.json',
	comment => 'JSON services config file (default services.json)',
);

opt threads => (
	isa     => 'Int',
	alias   => 't',
	default => 10,
	comment => 'Number of asynchronous requests (default 10)',
);

opt colored => (
	isa     => 'Bool',
	alias   => 'c',
	default => 0,
	comment => 'Colored output',
);

opt proxy => (
	isa     => 'Str',
	alias   => 'p',
	default => '',
	comment => 'Use proxy (like this http://localhost:8888/), not use it with --debugProxy',
);

opt debug => (
	isa     => 'Bool',
	alias   => 'd',
	default => 0,
	comment => 'Set debug mod',
);

opt debugProxy => (
	isa     => 'Bool',
	alias   => 'dp',
	default => 0,
	comment => 'Set charles debug proxy (http://localhost:8888/), not use it with --proxy',
);

my $opts = optargs;

$Getopt::Args::COLOUR = 1 if ($opts->{colored});

# Show header
HeaderInfo() if ($opts->{header} eq 'on');

# Show help
die usage() if ($opts->{help});

# Read config
my $config;
eval { $config = decode_json(read_file('config.json')); } if ($opts->{config});
if ($@) { say '[!] Can\'t read config file! ERROR: '.$@; exit; }

# Read services list
my $services;
eval { $services = decode_json(read_file('services.json')); };
if ($@) { say '[!] Can\'t read services list file! ERROR: '.$@; exit; }

# Set config 
$opts->{threads} = $config->{threads} if $config->{threads};
$opts->{in} = $config->{input} if $config->{input};
$opts->{good} = $config->{outputGood} if $config->{outputGood};
$opts->{bad} = $config->{outputBad} if $config->{outputBad};

# Open input file
open(INPUT, '<', $opts->{in}) or die "Can't open input file! File[".$opts->{in}."] Error[".$!."]";

my @coros;
for (1..$opts->{threads}) {
	push @coros, async {
		my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0 (X11; U; Linux i686; cs-CZ; rv:1.7.12) Gecko/20050929' );
		$ua->max_redirect(5);

		$ua->proxy(['http', 'https'] => 'http://localhost:8888') if ($opts->{debugProxy} and !$opts->{proxy});
		$ua->proxy(['http', 'https'] => $opts->{proxy}) if ($opts->{proxy} and !$opts->{debugProxy});

		while (my $hash = <INPUT>) {
			next unless (defined $hash);
			chomp($hash);

			for my $service (@{$services}) {
				unless ($hash =~ m#$service->{inputFilter}#) {
					sayError('Filtred hash! Service['.$service->{service}.' ('.$service->{hashType}.') ] '.
					'Hash['.$hash.'] Filter['.$service->{inputFilter}.']') if ($opts->{debug});
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
						sayGood($service->{service}, $service->{hashType}, $hash, $password);
						sayDebug($result->as_string) if ($opts->{debug});

						append_file( $opts->{good}, $hash.':'.$password."\t(".$service->{hashType}.")\n" ) ;
						last;
					} else {
						sayBad($service->{service}, $service->{hashType}, $hash);
						append_file( $opts->{bad}, $hash."\n" );
						sayDebug($result->as_string) if ($opts->{debug});
					}

				} elsif ($method eq 'POST') {
					$targetURL =~ s/\{HASH\}/$hash/g;
					$content->{$_} =~ s/\{HASH\}/$hash/g for (keys %{$content});

					my $result = $ua->post($targetURL, $content);
					my ($password) = $result->as_string =~ $service->{responsRegexp}; 

					if (defined $password) {
						sayGood($service->{service}, $service->{hashType}, $hash, $password);
						sayDebug($result->as_string) if ($opts->{debug});

						append_file( $opts->{good}, $hash.':'.$password."\t(".$service->{hashType}.")\n" ) ;
						last;
					} else {
						sayBad($service->{service}, $service->{hashType}, $hash);
						append_file( $opts->{bad}, $hash."\n" );
						sayDebug($result->as_string) if ($opts->{debug});
					}

				} else {
					sayError(
						'Undefined request method Method['.$service->{request}->{method}.'] '.
						'Service['.$service->{service}.' ('.$service->{hashType}.') ]'
					); next;
				}
			}
		}
	}
}

$_->join for (@coros);

close(INPUT);

sub HeaderInfo {
my $message = <<EOF;
# HashCracken v0.1
# Author: SHok
# GitHub.com https://github.com/maximusfox/pl-HashCracken
# Jabber: avchecking\@cryptovpn.com

EOF

print BRIGHT_WHITE.$message.RESET if ($opts->{colored});
print $message if (!$opts->{colored});

}

sub sayGood {
	my ($Servise,$HashType,$Hash,$Password) = @_;
	say BOLD.BRIGHT_GREEN.'[+]'.RESET.' '.
	BOLD.'Service'.RESET.'['.BRIGHT_CYAN.$Servise.RESET.' ('.BRIGHT_WHITE.$HashType.RESET.') ]'.RESET."\t".
	BRIGHT_MAGENTA.$Hash.RESET.BOLD.':'.RESET.BRIGHT_WHITE.$Password.RESET if ($opts->{colored});
	
	say '[+] Service['.$Servise.' ('.$HashType.') ]'."\t".$Hash.':'.$Password if (!$opts->{colored});
}

sub sayBad {
	my ($Servise,$HashType,$Hash) = @_;
	say BOLD.BRIGHT_YELLOW.'[-]'.RESET.' '.
	BOLD.'Service'.RESET.'['.BRIGHT_CYAN.$Servise.RESET.' ('.BRIGHT_WHITE.$HashType.RESET.') ]'.RESET."\t".
	$Hash.RESET if ($opts->{colored});

	say '[-] Service['.$Servise.' ('.$HashType.') ]'."\t".$Hash.RESET if (!$opts->{colored});
}

sub sayDebug {
	say BOLD.BRIGHT_RED.'DBG:'.RESET."\n".shift."\n".RESET if ($opts->{colored});
	say 'DBG:'."\n".shift."\n" if (!$opts->{colored});
}

sub sayError {
	say BOLD.BRIGHT_RED.'[!] '.RESET.shift.RESET if ($opts->{colored});
	say '[!] '.shift if (!$opts->{colored});
}