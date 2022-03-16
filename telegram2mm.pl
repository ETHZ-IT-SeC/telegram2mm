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
use IPC::Run qw( run );
use Data::Dumper;

###
### Constants / Hardcoded Telegram to Mattermost mappings
###

my %tg2mm_type = ( 'message' => 'post' );


###
### Helper functions
###

sub run2json {
    my ($in, $out, $err);
    my @mmctl_cmd = (@_, qw(--json));
    my $good_exitcodes = run(\@mmctl_cmd, \$in, \$out, \$err);
    # Debug mmctl calls
    #say "STDOUT:\n----\n$out\n----\n";
    #say "STDERR:\n----\n$err\n----\n";
    die '"'.join(' ', @_).'" exited with '." $? and this output:\n\n$err\n\n$out"
	unless $good_exitcodes;
    return decode_json($out);
}

sub date2epoch {
    # "* 1000" because Mattermost wants milliseconds
    return Mojo::Date->new(shift)->epoch()*1000;
}

sub transform_msg {
    my ($config, $msg) = @_;

    # All messages need to have a "type" field.
    die "Expected field \"type\" not found in ".encode_json($msg)
	unless (exists($msg->{type}) and $msg->{type} ne '');

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
Usage: $0 config.yml [telegram_export.json]

If no telegram export file is given as second parameter, the telegram
export is expected to be read from STDIN.
EOT
    exit (int($_[0]) || 0);
}


###
### Actual main code
###

# Read config, needs to be first parameter
my $config_file = shift;
&usage(1) unless -r $config_file && !-d _;
my $config = LoadFile($config_file) or &usage(2);

# Temporary Output ZIP file
my $tmpdir = $ENV{TMPDIR} // "/tmp";
my $zip_file = Mojo::File::tempfile("XXXXXXXXX",
				    DIR => $tmpdir,
				    SUFFIX => ".zip",
				    # Just for debugging
				    UNLINK => 0,
);

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

    $msg = transform_msg($config, $msg);

    $output .= encode_json($msg)."\n" if $msg;
}

# Create ZIP file needed by "mmctl import upload"
my $zip = Archive::Zip->new();
$zip->addDirectory( 'bulk-export-attachments/' );
my $jsonl_zip_member = $zip->addString( $output, 'mattermost_import.jsonl' );
$jsonl_zip_member->desiredCompressionMethod( COMPRESSION_DEFLATED );
$zip->writeToFileNamed($zip_file->to_string) == AZ_OK
    or die "Write error while writing to $zip_file";

# Automatically import the ZIP file into Mattermost
my ($json_return, $in, $out, $err);

# First upload the file
$json_return = run2json(qw(mmctl import upload), $zip_file);
my $upload_id = $json_return->[0]{id}
    or die "Returned ID from upload not found: ".Dumper($json_return);

# Figure out generated file name by grepping for the returned upload
# id (which is at the start of the generated file name).
$json_return = run2json(qw(mmctl import list available));
my $upload_filename = (grep { /^$upload_id/ } @$json_return)[0];

# Start to process that upload
$json_return = run2json(qw(mmctl import process), $upload_filename);
if ($json_return->[0]{status} ne 'pending') {
    die 'Process job state is not "pending": '.Dumper($json_return);
}
my $job_id = $json_return->[0]{id}
    or die "Returned ID from processing not found: ".Dumper($json_return);

# Wait until the import job is finished
my @mmctl_cmd = (qw(mmctl import job show), $job_id);
$json_return = run2json(@mmctl_cmd);
my $job_status = $json_return->[0]{status}
    or die "Job status not found in returned data: ".Dumper($json_return);

my $j = 1;
while ($job_status eq 'pending') {
    sleep (1);
    $json_return = run2json(@mmctl_cmd);
    $job_status = $json_return->[0]{status}
	or die "Job status not found in returned data: ".Dumper($json_return);
    say "[$j] Checking status for job ID $job_id: $job_status";
    $j++;
}

say 'Import job finished with status "'.$job_status.'".';

if ($job_status eq 'error') {
    say Dumper($json_return);
}
