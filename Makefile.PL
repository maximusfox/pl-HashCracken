#!/usr/bin/env perl

use strict;
use warnings;
 
use ExtUtils::MakeMaker;
 
WriteMakefile(
  NAME => 'pl-HashCracken',
  AUTHOR => 'SHok',
  LICENSE => 'perl_5',
  PREREQ_PM => {
    'Coro' => 6.33,
    'JSON::XS' => 3.01,
    'Coro::Select' => 6.33,
    'File::Slurp' => 9999.19,
    'LWP::UserAgent' => 6.05,
    'Term::ANSIColor' => 0,
  }
);