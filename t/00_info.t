#!/usr/bin/env perl

use warnings; 
use strict;

use Test::More qw/no_plan/; 

use_ok('SNAG');

diag
(
  "Testing SNAG $SNAG::VERSION, Perl $], $^X ",
  "Perl $], ",
  "$^X on $^O"
);
my $snag = new SNAG(config_path => ['t/lib/']);
#diag "Foo: " . $snag->OS;

# make a basic object
cmp_ok(ref($snag), 'eq', 'SNAG', 'snag object');

# Check default OS detection, we probably want something better than just 
# checking ne defaults
cmp_ok($snag->OS, 'ne', '__OS__', 'OS detection');
cmp_ok($snag->OSVER, 'ne', '__OSVER__', 'OS version detection');
cmp_ok($snag->OSLONG, 'ne', '__OSLONG__', 'OS long detection');
cmp_ok($snag->OSDIST, 'ne', '__OSDIST__', 'OS dist detection');

# checking some more defaults
cmp_ok($snag->REC_SEP, 'eq', '~_~', 'REC_SEP');
cmp_ok($snag->RRD_SEP, 'eq', ':', 'RRD_SEP');
cmp_ok($snag->LINE_SEP, 'eq', '_@%_', 'LINE_SEP');
cmp_ok($snag->PARCEL_SEP, 'eq', '@%~%@', 'PARCEL_SEP');
cmp_ok($snag->INFO_SEP, 'eq', ':%:', 'INFO_SEP');

# check the config defaults
cmp_ok($snag->SMTP, 'eq', 'smtp.example.com', 'smtp config check');
cmp_ok($snag->SENDTO, 'eq', 'somebody@something.com', 'email check');
cmp_ok($snag->BASE_DIR, 'eq', '/opt/snag', 'base dir');
cmp_ok($snag->LOG_DIR, 'eq', '/opt/snag/log', 'log dir');
cmp_ok($snag->TMP_DIR, 'eq', '/opt/snag/tmp', 'tmp dir');
cmp_ok($snag->STATE_DIR, 'eq', '/opt/snag/tmp', 'state dir');
cmp_ok($snag->CFG_DIR, 'eq', '/opt/snag/conf', 'conf dir');

# Let's fire off something and see if it's already running
cmp_ok($snag->already_running(), 'eq', '0', 'Am I running?');
# TODO test for something already running
# TODO test daemonize

# Make sure we capture the running name
cmp_ok($snag->SCRIPT_NAME, 'eq', '00_info.t');



