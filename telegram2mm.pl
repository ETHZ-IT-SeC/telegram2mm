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
use utf8;

use Mojo::JSON qw(decode_json encode_json);
use Mojo::Date;
use Mojo::File;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use YAML::Tiny qw(LoadFile);
use IPC::Run qw( run );
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::ISO8601;
use Data::Dumper;
use File::Rename;

###
### Constants / Hardcoded Telegram to Mattermost mappings
###

my %tg2mm_type = ( 'message' => 'post' );
my @text_types_to_convert_to_plain_text =
    (qw(link bot_command mention email text_link phone hashtag cashtag bank_card));

# Global variable which can be overriden via configuration file.
my $tzobj = DateTime::TimeZone->new( name => 'Etc/UTC');

###
### Global settings
###

# It seems as if the Telegram export only contains file names in
# UTF-8, so assume that for now. Otherwise Archive::ZIP doesn't create
# correct ZIP archives:
#
# Wide character in print at /usr/lib/x86_64-linux-gnu/perl-base/IO/Handle.pm line 157.
# Wide character in print at /usr/lib/x86_64-linux-gnu/perl-base/IO/Handle.pm line 157.
#
# $ unzip -l /tmp/telegram2mm_BcUyuEF0C.zip
# warning [/tmp/telegram2mm_BcUyuEF0C.zip]:  6 extra bytes at beginning or within zipfile
#   (attempting to process anyway)
# error [/tmp/telegram2mm_BcUyuEF0C.zip]:  start of central directory not found;
#   zipfile corrupt.
#   (please check that you have transferred or created the zipfile in the
#   appropriate BINARY mode and that you have compiled UnZip properly)
#
$Archive::Zip::UNICODE = 1;

# Call the main routine if we're not sourced. Allows unit testing of
# functions in here.
main(@ARGV) unless caller(0);

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
    my $tg_time = shift;

    # First we must figure out if the time given in here is DST or
    # not. The time stamp in Telegrams result.json looks like this
    # one, e.g. without time zone or DST flag: "2022-05-23T13:23:42"
    #
    # For that we do assume UTC, calculate the offset and then declare
    # this as the offset of the time stamp. This will make the
    # timestamp wrong twice a year for as manu hours as the offset
    # is. For most countries in Europe this is a few hours hour per
    # year. IMHO acceptable compared to the effort needed to and brain
    # knot caused by trying to fix this properly. DST must die!
    my $dt_tg_time = DateTime::Format::ISO8601->parse_datetime($tg_time);
    my $tz_offset =
	DateTime::TimeZone->offset_as_string(
	    $tzobj->offset_for_datetime($dt_tg_time), ':');
    my $export_time = "$tg_time$tz_offset";

    # "* 1000" because Mattermost wants milliseconds
    return Mojo::Date->new($export_time)->epoch()*1000;
}

sub transform_msg {
    my ($config, $msg, $replies, $attachments) = @_;

    # All messages need to have a "type" field.
    die "Expected field \"type\" not found in ".encode_json($msg)
	unless (exists($msg->{type}) and $msg->{type} ne '');

    # Rename type if necessary.
    $msg->{type} = $tg2mm_type{$msg->{type}}
	if exists $tg2mm_type{$msg->{type}};

    if ($msg->{type} eq "post") {
	# Simply return the existing object if the message already has
	# been transformed due to being a reply.
	if (exists($msg->{post}) and ref($msg->{post}) eq 'HASH') {
	    return $msg;
	}

	# Skip this message with a warning if the user is unknown
	unless (exists $config->{users}{$msg->{from_id}}) {
	    warn "User ID ".$msg->{from_id}." unknown, skipping this message\n";
	    return undef;
	}

	# Flatten text component in case it's an array ref
	if (ref($msg->{text}) eq 'ARRAY') {
	    my $new_text = join('', map {
		my $text_element = $_;
		# if #_ is a hashref
		if (ref($text_element) eq 'HASH') {
		    if (exists($text_element->{type}) and
			exists($text_element->{text}) and
			grep { $text_element->{type} eq $_ } @text_types_to_convert_to_plain_text) {
			$text_element->{text}
		    } elsif (exists($text_element->{type}) and
			     exists($text_element->{text}) and
			     $text_element->{type} eq 'code') {
			' `'.$text_element->{text}.'` ';
		    } elsif (exists($text_element->{type}) and
			     exists($text_element->{text}) and
			     $text_element->{type} eq 'bold') {
			'**'.$text_element->{text}.'**';
		    } elsif (exists($text_element->{type}) and
			     exists($text_element->{text}) and
			     $text_element->{type} eq 'italic') {
			'_'.$text_element->{text}.'_';
		    } elsif (exists($text_element->{type}) and
			     exists($text_element->{text}) and
			     $text_element->{type} eq 'underline') {
			'**_'.$text_element->{text}.'_**';
		    } elsif (exists($text_element->{type}) and
			     exists($text_element->{text}) and
			     $text_element->{type} eq 'strikethrough') {
			'~~'.$text_element->{text}.'~~';
		    } elsif (exists($text_element->{type}) and
			     exists($text_element->{text}) and
			     $text_element->{type} eq 'pre') {
			"\n".'```'."\n".$text_element->{text}."\n".'```'."\n";
		    } elsif (exists($text_element->{type}) and
			     exists($text_element->{text}) and
			     $text_element->{type} eq 'mention_name') {
			'@'.$config->{users}{'user'.$text_element->{user_id}};
		    } else {
			die "Yet unsupported message format (no type, no text or known type): ".Dumper($msg);
		    }
		# if $_ is no reference
		} elsif (ref($text_element) eq '') {
		    $text_element;
		} else {
		    die "Yet unsupported message format (text element is neithe hashref not scalar): ".Dumper($msg);
		}
				} @{$msg->{text}});
	    $msg->{text} = $new_text;
	} elsif ($msg->{text} eq '' and
		 exists($msg->{sticker_emoji})) {
	    $msg->{text} = $msg->{sticker_emoji};
	}

	# Add post subelement
	$msg->{post} = {
	  team      => $config->{import_into}{team},
	  channel   => $config->{import_into}{channel},
	  message   => $msg->{text},
	  user      => $config->{users}{$msg->{from_id}},
	  create_at => date2epoch($msg->{date}),
	};

	if (exists($msg->{file}) and
	    not (exists($msg->{media_type}) and $msg->{media_type} eq 'sticker')) {
	    $msg->{post}{attachments} //= [];
	    $msg->{post}{props} //= { attachments => [] },
	    # Add metadata to message object
	    push(@{$msg->{post}{attachments}}, {
		'path' => $config->{attachment_base_dir}.'/'.$msg->{file}
	    });
	    # Remember file to being added to ZIP file later
	    push(@$attachments, $msg->{file});
	}

	if (exists($msg->{photo})) {
	    $msg->{post}{attachments} //= [];
	    $msg->{post}{props} //= { attachments => [] },
	    # Add metadata to message object
	    push(@{$msg->{post}{attachments}}, {
		'path' => $config->{attachment_base_dir}.'/'.$msg->{photo}
	    });
	    # Remember file to being added to ZIP file later
	    push(@$attachments, $msg->{photo});
	}

	# Cleanup
	delete $msg->{text};
	delete $msg->{from};
	delete $msg->{date};
	delete $msg->{sticker_emoji};
	delete $msg->{file};
	delete $msg->{photo};
	delete $msg->{width};
	delete $msg->{height};
	delete $msg->{mime_type};
	delete $msg->{thumbnail};
	delete $msg->{media_type};
	unless ($replies->{$msg->{id}}) {
	    delete $msg->{from_id};
	    delete $msg->{id};
	}
    }

    return $msg;
}

sub sanitize_attachment_file_name {
    my ($filename, $basedir) = @_;
    if ($filename !~ m(^[-A-Za-z0-9_@=+:.,/]+$)) {
	my $newname = $filename;
	rename(
	    [ $filename ],
	    sub { $_ =~ s([^/A-Za-z0-9_\@=+:.,-])(_)g }
	    );
    } else {
	return $filename;
    }
}

sub attach_replies {
    my ($config, $msg, $replies, $attachments) = @_;
    return unless $msg->{type} eq 'post';

    my $my_replies = $replies->{$msg->{id}};
    $msg->{post}{replies} = [];

    foreach my $reply (@$my_replies) {
	$reply = transform_msg($config, $reply, $replies, $attachments);
	# Make a reply out of the message
	$reply = $reply->{post};
	delete($reply->{channel});
	delete($reply->{team});

	# Attach the reply to the message
	push(@{$msg->{post}{replies}}, $reply);

	if (exists($reply->{id}) and exists($replies->{$reply->{id}})) {
	    attach_replies($config, $msg, $replies->{$reply->{id}});
	}

	delete($msg->{id});
	delete($msg->{from_id});
    }
}

sub usage {
    print <<EOT;
Usage: $0 config.yml [telegram_export.json]

If no telegram export file is given as second parameter, the telegram
export is expected to be read from STDIN.
EOT
    exit (int($_[0]) || 0);
}

sub load_config {
    my $config_file = shift;
    &usage(1) unless -r $config_file && !-d _;
    my $config = LoadFile($config_file) or &usage(2);

    # Timezone handling
    if (exists $config->{timezone}) {
	my $tz = $config->{timezone};

	# Check if the timezone name in the config file is valid
	unless (DateTime::TimeZone->is_valid_name($tz)) {
	    die "\"$tz\" is not a valid timezone name. ".
		'Use e.g. "UTC" or "Europe/Busingen".'."\n";
	}

	# Recreate the global timezone object for later use
	$tzobj = DateTime::TimeZone->new( name => $tz );
    }

    return $config;
}

sub recursively_find_reply_to_message_id {
    my ($msg_id, $reply_to) = @_;
    if (exists $reply_to->{$msg_id}) {
	return
	    recursively_find_reply_to_message_id($reply_to->{$msg_id},
						 $reply_to);
    } else {
	return $msg_id;
    }
}

sub tg_json_to_mm_jsonl {
    my ($config, $tg_json, $attachments) = @_;
    my $tg = decode_json($tg_json);

    # First convert to JSON Lines (aka JSONL)
    my @messages = @{$tg->{messages}};

    # First track replies as they might be referred to in later (but not
    # earlier) messages. That way we have the data when the message to
    # which has been replied to, is processed.
    my %reply_to = ();
    my %message_by_id = ();
    # Track forward chain first, as we need to follow their chains in the next step
    foreach my $msg (@messages) {
	$message_by_id{$msg->{id}} = $msg;
	if (exists $msg->{reply_to_message_id}) {
	    $reply_to{$msg->{id}} = $msg->{reply_to_message_id};
	}
    }

    my %replies = ();
    foreach my $msg (@messages) {
	if (exists $msg->{reply_to_message_id}) {
	    # Follow the chain
	    my $top_most_parent =
		recursively_find_reply_to_message_id($msg->{reply_to_message_id},
						     \%reply_to);
	    # Backward
	    $replies{$top_most_parent} //= [];
	    push(@{$replies{$top_most_parent}}, $msg);
	}
    }

    # The actual conversion loop
    my $output = '{"type":"version","version":1}'."\n";
    my $i = 0;
    foreach my $msg (@messages) {
	# Skip type "service for now
	next if (exists $msg->{type}) and $msg->{type} eq 'service';

	# Transform the actual message
	$msg = transform_msg($config, $msg, \%replies, $attachments);

	# Attach potential replies
	if (exists($msg->{id}) and exists($replies{$msg->{id}})) {
	    attach_replies($config, $msg, \%replies, $attachments);
	}

	# Only further processs a message if it wasn't a reply and hasn't
	# been emptied.
	if ($msg and %$msg and not exists($msg->{reply_to_message_id})) {
	    # Actually create the JSON line
	    $output .= encode_json($msg)."\n"
	}
    }

    return $output;
}


###
### Actual main code
###

sub main {
    # Read config, needs to be first parameter
    my $config = load_config(shift);
    my $tg_json_file = shift;
    my $tg_json_mojo = Mojo::File->new($tg_json_file);
    my @attachments = ();
    my $pwd = `pwd`; chomp($pwd);
    $config->{attachment_base_dir} = $pwd.'/'.$tg_json_mojo->dirname;


    # Temporary Output ZIP file
    my $tmpdir = $ENV{TMPDIR} // "/tmp";
    my $zip_file = Mojo::File::tempfile("telegram2mm_XXXXXXXXX",
					DIR => $tmpdir,
					SUFFIX => ".zip",
					# Just for debugging
					#UNLINK => 0,
    );

    # Read JSON from whereever it comes from (slurp mode)
    my $tg_json = $tg_json_mojo->slurp();

    # Main conversion routine
    my $output = tg_json_to_mm_jsonl($config, $tg_json, \@attachments);

    #die Dumper \@attachments;

    # Create ZIP file needed by "mmctl import upload"
    my $zip = Archive::Zip->new();

    foreach my $dir (qw(photos files video_files voice_messages)) {
	say "$zip_file: Creating \"data/$dir\"";
	$zip->addDirectory( "data/$dir" );
    }

    do {
	no warnings 'utf8';

    foreach my $attachment (@attachments) {
	say "$zip_file: Adding \"$attachment\".";
	my $added_file = $zip->addFile(
	    $config->{attachment_base_dir}.'/'.$attachment,
	    "data/$attachment",
	    COMPRESSION_LEVEL_NONE
	    );
    }

    my $jsonl_zip_member = $zip->addString( $output, 'mattermost_import.jsonl' );
    $jsonl_zip_member->desiredCompressionMethod( COMPRESSION_DEFLATED );
    say "Writing \"$zip_file\".";
    $zip->writeToFileNamed($zip_file->to_string) == AZ_OK
	or die "Write error while writing to $zip_file";

    #die "$zip_file:\n\n".`ls -lh $zip_file`;
    #die "$zip_file:\n\n".`als $zip_file; ls -lh $zip_file; file $zip_file; strings $zip_file|head`;
    };

    # Automatically import the ZIP file into Mattermost
    my ($json_return, $in, $out, $err);

    # First upload the file
    $json_return = run2json(qw(mmctl import upload), $zip_file);
    my $upload_id = $json_return->[0]{id}
	or die "Returned ID from upload not found: ".Dumper($json_return);

    # Figure out generated file name by grepping for the returned
    # upload id (which is at the start of the generated file name).
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
    while ($job_status eq 'pending' or $job_status eq 'in_progress') {
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
}
# End of main() routine.
