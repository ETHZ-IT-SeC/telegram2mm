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
ok( $config = load_config("$FindBin::Bin/mock/import_config.yml"),
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
	       }
	   },
	   'Config is read as expected' );

# Telegram date format is ISO-8601 but without timezone.
is( date2epoch("2022-03-25T17:30:36"), 1648229436*1000,
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
		       'create_at' => 1647324371000,
		   }},
	   'A simple message is transformed as expected' );
is_deeply( transform_msg(
	       $config,
	       {
		   'id' => 123456,
		   'type' => 'message',
		   'date' => '2022-03-15T06:06:11',
		   'from' => 'A. B. Cexample',
		   'from_id' => 'user123',
		   'text' => [
		       {
			   'text' => '/me',
			   'type' => 'bot_command'
		       },
		       ' says ',
		       {
			   'text' => 'something italic',
			   'type' => 'italic'
		       },
		       ' to ',
		       {
			   'text' => 'Anna',
			   'user_id' => 123,
			   'type' => 'mention_name'
		       },
		       ' with umläuts and ',
		       {
			   'text' => 'boldly emphasized',
			   'type' => 'bold'
		       },
		       ' text as well as some ',
		       {
			   'text' => 'code snippet',
			   'type' => 'code'
		       },
		       ' and some ',
		       {
			   'text' => '$cashtag',
			   'type' => 'cashtag'
		       },
		       ', pointing to ',
		       {
			   'text' => 'https://www.example.com/',
			   'type' => 'link'
		       },
		       ' and ',
		       {
			   'text' => 'www.example.org',
			   'href' => 'https://www.example.org/',
			   'type' => 'text_link'
		       },
		       ' as well as mentioning ',
		       {
			   'text' => 'example@example.com',
			   'type' => 'email'
		       },
		       ', ',
		       {
			   'text' => 'not',
			   'type' => 'underline'
		       },
		       ' ',
		       {
			   'text' => '.org',
			   'type' => 'strikethrough'
		       },
		       ' ',
		       {
			   'text' => '2022051201133400',
			   'type' => 'bank_card'
		       },

		       # TODO: mention, phone
		       # TODO: really two blanks around "code" snippets?
		   ]
	       }, {}),
	       {
		   'type' => 'post',
		   'post' => {
		       'team' => 'example',
		       'channel' => 'town square',
		       'user' => 'abc',
		       'message' =>
			   '/me says _something italic_ to @abc with umläuts and **boldly emphasized** text as well as some  `code snippet`  and some $cashtag, pointing to https://www.example.com/ and www.example.org as well as mentioning example@example.com, **_not_** ~~.org~~ 2022051201133400',
		       'create_at' => 1647324371000,
		   }
	       },
	   'A complex message is transformed as expected' );

is_deeply( transform_msg(
	       $config,
	       {
		   'id' => 123456,
		   'type' => 'message',
		   'date' => '2022-03-15T06:06:11',
		   'from' => 'A. B. Cexample',
		   'from_id' => 'user123',
		   'text' => [
		       "Some multiline code snippet:\n\n",
		       {
			   'text' => "foo\nbar\nfnord",
			   'type' => 'pre'
		       }
		   ]
	       }, {}),
	       {
		   'type' => 'post',
		   'post' => {
		       'team' => 'example',
		       'channel' => 'town square',
		       'user' => 'abc',
		       'message' =>
			   "Some multiline code snippet:\n\n\n".'```'.
			   "\nfoo\nbar\nfnord\n".'```'."\n",
			   'create_at' => 1647324371000,
			   # TODO: Really three newlines?
		   }
	       },
	   'A complex message is transformed as expected' );

is_deeply( transform_msg(
	       $config,
	       {
		   'id' => 123456,
		   'type' => 'message',
		   'date' => '2022-03-15T06:06:11',
		   'from' => 'A. B. Cexample',
		   'from_id' => 'user123',
		   'text' => [
		       "Some multiline code snippet:\n\n",
		       {
			   'text' => "foo\nbar\nfnord",
			   'type' => 'pre'
		       }
		   ]
	       }, {}),
	       {
		   'type' => 'post',
		   'post' => {
		       'team' => 'example',
		       'channel' => 'town square',
		       'user' => 'abc',
		       'message' =>
			   "Some multiline code snippet:\n\n\n".'```'.
			   "\nfoo\nbar\nfnord\n".'```'."\n",
			   'create_at' => 1647324371000,
			   # TODO: Really three newlines?
		   }
	       },
	   'A message with pre-formatted code is transformed as expected' );

# Check JSON transformation of a simple chat
is_deeply( tg_json_to_mm_jsonl($config, <<'EOT' ),
{
 "name": "telegram2mm Example Chat Group",
 "type": "private_supergroup",
 "id": 123456,
 "messages": [
  {
   "id": 12345678,
   "type": "message",
   "date": "2022-03-15T06:06:11",
   "from": "A. B. Cexample",
   "from_id": "user123",
   "text": "Morning!"
  },
  {
   "id": 12345679,
   "type": "message",
   "date": "2022-03-15T06:07:51",
   "from": "D. E. Fexample",
   "from_id": "user456",
   "text": "Mornin'!"
  }
 ]
}
EOT
	   <<'EOT',
{"type":"version","version":1}
{"post":{"channel":"town square","create_at":1647324371000,"message":"Morning!","team":"example","user":"abc"},"type":"post"}
{"post":{"channel":"town square","create_at":1647324471000,"message":"Mornin'!","team":"example","user":"def"},"type":"post"}
EOT
	   'A whole JSON TG import is transformed to MM JSONL as expected' );

is( tg_json_to_mm_jsonl($config, <<'EOT' ),
{
 "name": "telegram2mm Example Chat Group",
 "type": "private_supergroup",
 "id": 123456,
 "messages": [
  {
   "id": 12345678,
   "type": "message",
   "date": "2022-03-15T06:06:11",
   "from": "A. B. Cexample",
   "from_id": "user123",
   "text": "Morning!"
  },
  {
   "id": 12345679,
   "type": "message",
   "date": "2022-03-15T06:07:51",
   "from": "D. E. Fexample",
   "from_id": "user456",
   "text": "Mornin'!",
   "reply_to_message_id": 12345678
  }
 ]
}
EOT
	   <<'EOT',
{"type":"version","version":1}
{"post":{"channel":"town square","create_at":1647324371000,"message":"Morning!","replies":[{"create_at":1647324471000,"message":"Mornin'!","user":"def"}],"team":"example","user":"abc"},"type":"post"}
EOT
	   'A whole JSON TG import containing replies is transformed to MM JSONL as expected' );

is( tg_json_to_mm_jsonl($config, <<'EOT' ),
{
 "name": "telegram2mm Example Chat Group",
 "type": "private_supergroup",
 "id": 123456,
 "messages": [
  {
   "id": 12345678,
   "type": "message",
   "date": "2022-03-15T06:06:11",
   "from": "A. B. Cexample",
   "from_id": "user123",
   "text": "Morning!"
  },
  {
   "id": 12345679,
   "type": "message",
   "date": "2022-03-15T06:07:51",
   "from": "D. E. Fexample",
   "from_id": "user456",
   "text": "Mornin'!",
   "reply_to_message_id": 12345678
  },
  {
   "id": 12345680,
   "type": "message",
   "date": "2022-03-15T06:09:31",
   "from": "G. H. Ixample",
   "from_id": "user789",
   "text": "Good Morning!",
   "reply_to_message_id": 12345679
  }
 ]
}
EOT
	   <<'EOT',
{"type":"version","version":1}
{"post":{"channel":"town square","create_at":1647324371000,"message":"Morning!","replies":[{"create_at":1647324471000,"message":"Mornin'!","user":"def"},{"create_at":1647324571000,"message":"Good Morning!","user":"ghi"}],"team":"example","user":"abc"},"type":"post"}
EOT
	   'A whole JSON TG import containing nested replies is transformed to MM JSONL as expected' );

# Stickers
is_deeply( transform_msg(
	       $config,
	       {
		   'id' => 123456,
		   'type' => 'message',
		   'date' => '2022-03-15T06:06:11',
		   'from' => 'A. B. Cexample',
		   'from_id' => 'user123',
		   'text' => '',
		   'file' => 'stickers/sticker.webp',
		   'thumbnail' => 'stickers/sticker.webp_thumb.jpg',
		   'media_type' => 'sticker',
		   'sticker_emoji' => '🤦‍♂️',
	       }, {}),
	       {
		   'type' => 'post',
		   'post' => {
		       'team' => 'example',
		       'channel' => 'town square',
		       'user' => 'abc',
		       'message' => '🤦‍♂️',
		       'create_at' => 1647324371000,
		   }},
	   'A sticker message is transformed as expected' );

done_testing();
