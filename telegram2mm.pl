#!/usr/bin/perl

# Telegram Export to Mattermost Import conversion script
#
# Author: Axel Beckert <axel@ethz.ch>
# Copyright 2022 ETH Zurich IT Security Center
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see https://www.gnu.org/licenses/.

use strict;
use warnings;
use 5.010;

use Mojo::JSON qw(decode_json encode_json);
use Mojo::Date;
use Mojo::File;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use YAML::Tiny qw(LoadFile);

# Constants
my %tg2mm_type = ( 'message' => 'post' );

# Read config, needs to be first parameter
my $config_file = shift;
&usage(1) unless -r $config_file && !-d _;
my $config = LoadFile($config_file) or &usage(2);

# Output ZIP file, needs to be second parameter
my $zip_file = shift;
die "$zip_file already exists" if -e $zip_file;

# Read JSON from whereever it comes from (slurp mode)
local $/ = undef;
my $tg_json = <>;
my $tg = decode_json($tg_json);

# First convert to JSON Lines (aka JSONL)
my @messages = @{$tg->{messages}};

my $output = '{"type":"version","version":1}'."\n";
my $i = 0;
foreach my $msg (@messages) {
    # Skip group creation for now
    next if (exists $msg->{action} and $msg->{action} eq 'create_group');

    $msg = transform_msg($msg);

    $output .= encode_json($msg)."\n" if $msg;

    # For debugging: Only import the first n messages or so.
    last if ++$i > 3;
}

# Create ZIP file needed by "mmctl import upload"
my $zip = Archive::Zip->new();
$zip->addDirectory( 'bulk-export-attachments/' );
my $jsonl_zip_member = $zip->addString( $output, 'mattermost_import.jsonl' );
$jsonl_zip_member->desiredCompressionMethod( COMPRESSION_DEFLATED );
$zip->writeToFileNamed($zip_file) == AZ_OK
    or die "Write error while writing to $zip_file";

###
### Helper functions
###

sub date2epoch {
    # "* 1000" because Mattermost wants milliseconds
    return Mojo::Date->new(shift)->epoch()*1000;
}

sub transform_msg {
    my $msg = shift;

    # All messages need to have a "type" field.
    die "Expected field \"type\" not found in ".encode_json($msg)
	unless exists $msg->{type} and $msg->{type} ne '';

    # Rename type if necessary.
    $msg->{type} = $tg2mm_type{$msg->{type}}
	if exists $tg2mm_type{$msg->{type}};

    if ($msg->{type} eq "post") {
	# Skip this message with a warning if the user is unknown
	unless (exists $config->{users}{$msg->{from_id}}) {
	    warn "User ID ".$msg->{from_id}." unknown, skipping this message\n";
	    return undef;
	}

	# Add post subelement
	$msg->{post} = {
	  team      => $config->{import_into}{team},
	  channel   => $config->{import_into}{channel},
	  message   => $msg->{text},
	  user      => $config->{users}{$msg->{from_id}},
	  create_at => date2epoch($msg->{date}),
	};

	delete $msg->{text};
	delete $msg->{from};
	delete $msg->{from_id};
	delete $msg->{id};
	delete $msg->{date};
    }

    return $msg;
}

sub usage {
    print <<EOT;
Usage: $0 config.yml output.zip [telegram_export.json]

If no telegram export file is given as second parameter, the telegram
export is expected to be read from STDIN.
EOT
    exit (int($_[0]) || 0);
}

