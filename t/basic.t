#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

my $default_path = $ENV{PATH};

require "$FindBin::Bin/../telegram2mm.pl";

# Telegram date format is ISO-8601 UTC, but without the "Z".
is( date2epoch("2022-03-25T17:30:36"), 1648229436*1000,
    "date2epoch() returns epoch in milliseconds" );

# Check "mmctl export list" output parsing with a mocked mmctl
$ENV{PATH} = "$FindBin::Bin/mock/list";
is_deeply( run2json(qw(mmctl export list)),
	   [ 'sr83ztmhrjneiffottxrpkjota_export.zip' ],
	   'run2json() works as expected'
    );
$ENV{PATH} = $default_path;





done_testing();
