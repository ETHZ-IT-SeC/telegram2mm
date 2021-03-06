#!/usr/bin/perl

use strict;
use warnings;
use 5.010;
use utf8;
use Test::More;
use FindBin;

my $default_path = $ENV{PATH};

require "$FindBin::Bin/../telegram2mm.pl";

# Check "mmctl export list" output parsing with a mocked mmctl
$ENV{PATH} = "$FindBin::Bin/mock/list";
is_deeply( run2json(qw(mmctl export list)),
	   [ 'sr83ztmhrjneiffottxrpkjota_export.zip' ],
	   'run2json() works as expected'
    );
$ENV{PATH} = $default_path;

# Check Config Loading
my $config;
ok( $config = load_config("$FindBin::Bin/mock/import_config_tz.yml"),
    'Loading the example config worked' );
is_deeply( $config,
	   {
	       'users' => {
		   'user123' => 'abc',
		   'user789' => 'ghi',
		   'user456' => 'def'
	       },
	       'import_into' => {
		   'team' => 'example',
		   'channel' => 'town square'
	       },
	       'timezone' => 'Europe/Busingen',
	   },
	   'Config with timezone is read as expected' );

# Telegram date format is ISO-8601 but without timezone.
is( date2epoch("2022-03-25T17:30:36"), 1648225836*1000,
    "date2epoch() returns epoch in milliseconds" );

# Check and Message Transformation
is_deeply( transform_msg(
	       $config,
	       {
		   'id' => 123456,
		   'type' => 'message',
		   'date' => '2022-03-15T06:06:11',
		   'from' => 'A. B. Cexample',
		   'from_id' => 'user123',
		   'text' => 'Morning!'
	       }, {}),
	       {
		   'type' => 'post',
		   'post' => {
		       'team' => 'example',
		       'channel' => 'town square',
		       'user' => 'abc',
		       'message' => 'Morning!',
		       'create_at' => 1647320771000,
		   }},
	   'A message with configured timezone is transformed as expected' );

done_testing();
