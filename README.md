Import Telegram Group Chat History into a Mattermost Channel
============================================================

Description
-----------

The Perl script `telegram2mm.pl` imports a
[Telegram](https://telegram.org/)
[group](https://telegram.org/faq?setln=en#q-what-39s-the-difference-between-groups-and-channels)
export into a [Mattermost](https://mattermost.com/) channel using
Mattermost's `mmctl import` set of commands (not the older `mattermost
import` set of commands).


State
-----

The tool is currently working well (tested with versions between
Mattermost 7.5.1 and at least 9.5.1) but so far does not support all
functionality which might be used on Telegram.

### Working

- Support for importing Telegram Channels/Supergroups/Megagroups into Mattermost Channels.
- Support for replies
- Support for attachments (images, videos, PDF, etc.)
- Workaround for Telegram's export neither containing timezones
  nor DST flags. (This has been fixed in Telegram exports recently by
  also including the date in timezone independent Unix
  timestamps. `telegram2mm` does though currently not rely on them and
  hence still can import older Telegram exports without this
  additional field.)
- Support for importing Telegram Personal Chats into Mattermost Direct
  Channels.

### Untested

- Importing non-private Supergroups. (Probably just works, but might
  be non-trivial wrt. to user management.)
- Importing Telegram Forums, Basic Groups or Gigagroups.
- Bots in groups
- Support for voice messages
- Support for video messages

### Not implemented

- Support for emoji reactions—due to [emoji reactions are missing in
  JSON exports](https://github.com/telegramdesktop/tdesktop/issues/16890).
- Channel creation

### Not planned to be supported

- Import of users
- Pinned messages.


Synopsis
--------

```
./telegram2mm.pl ../import_config.yml ../ChatExport_2022-03-02/result.json
```


Configuration
-------------

### Login first

Before you first use this tool or if the get the error message
`Error: : Invalid or expired session, please login again.`, you need
to make `mmctl` to store a login token first:

```
mmctl auth login https://mattermost.example.org/ --name local --username adminusername
```

you first need to login again.


### Configuration file

`telegram2mm.pl` expects a [YAML](https://yaml.org/) written configuration file.

#### Example configuration file

```yaml
# telegram2mm import configuration
---
users:
  # Anna Mustermann
  user1234: annaiscool

  # Berta Beispiel
  user4321: bertarocks

  # Charles Example
  user5678: charly

import_into:
  team: your-team-name
  channel: town-square

timezone: Europe/Busingen
```

#### Configuration File Explanation

The `user<telegram_user_id>` keywords are the values in the `from_id`
JSON field in the chat export file. The value behind them is the user
name (without the `@`) of the according person on the Mattermost
server.

Lines which have a `#` as first non-blank character are comments.

The timezone is the timezone which should be assumed for the time
stamps in Telegram's chat export.  If no timezone is given, UTC is
assumed.

### Chat Export File

The chat export file is what you get when you click on the
per-group-chat menu (top right three dots menu in the [Telegram
Desktop](https://desktop.telegram.org/) application) and click on
"Export Chat History" (or similar depending on localisation) and
choose the "JSON" format.

The export feature has been [introduced in Telegram Desktop 1.3.13 on
27th of August 2018](https://telegram.org/blog/export-and-more).
`telegram2mm` though has only been tested with Telegram Desktop
versions 3.5.2, 3.6.0, 3.7.3 and 4.3.1 so far. We though assume that
exports from all Telegram Desktop versions since at least 3.5.0 work
fine with `telegram2mm`.


Example Run
-----------

```
$ ./telegram2mm.pl ../import_config.yml ../ChatExport_2022-03-02/result.json
[1] Checking status for job ID yuy3gj8e5fnj8d3eugt4gkx5me: pending
[2] Checking status for job ID yuy3gj8e5fnj8d3eugt4gkx5me: pending
[3] Checking status for job ID yuy3gj8e5fnj8d3eugt4gkx5me: pending
[4] Checking status for job ID yuy3gj8e5fnj8d3eugt4gkx5me: pending
[5] Checking status for job ID yuy3gj8e5fnj8d3eugt4gkx5me: pending
[6] Checking status for job ID yuy3gj8e5fnj8d3eugt4gkx5me: in_progress
[7] Checking status for job ID yuy3gj8e5fnj8d3eugt4gkx5me: success
Import job finished with status "success".
$
```


Requirements
------------

* [Mattermost](https://mattermost.com/) needs to be installed and the
  `mmctl` commandline tool needs to in `$PATH`.
  
  * For attachments to work properly, Mattermost is recommended to be
    at least at version 7.5.1 as this version is tested and
    known to work. Mattermost versions before 7.4.0 were
    [known to be buggy](https://github.com/mattermost/mattermost-server/pull/20978)
    and [to crash on bulk imports](https://forum.mattermost.com/t/import-from-jsonl-ignores-attachments-despite-no-error-messages-and-success-at-the-end/13472/7),
    at least when using earlier (buggy) versions of `telegram2mm`. And
    it is not known if the fixed version of `telegram2mm` still causes
    these crashes with Mattermost before 7.4.0.
  
  * Additionally, in case of media files or other attachments in the
    Telegram export, `MaxFileSize` in
    `/opt/mattermost/config/config.defaults.json` needs to be raised
    to be higher than whatever `du -s ChatExport_[…]` says. In my case I
    used ca. 1 GB as the `ChatExport_[…]` directory was around 750 MB:
    
    
    ```
    "MaxFileSize": 104857600,
    ```

  * If you don't use `http://127.0.0.1:8065/` for logging in with
    `mmctl` (e.g. `mmctl auth login http://127.0.0.1:8065/ --name
    local --username admin`), you might also need to raise the upper
    limit of the size of `POST` requests in Nginx, too, something like
    
    ```
    client_max_body_size 1G;
    ```
    
    (I guess) in `/etc/nginx/conf.d/mattermost.conf`. You might want
    to undo this later again to avoid users uploading huge files as
    attachment to Mattermost posts. 😎

* Besides [Perl](https://www.perl.org/) (at least version 5.10) and
  some modules from the [Perl
  Core](https://www.perl.com/article/what-is-the-perl-core-/) (like
  `IPC::Run` and `Data::Dumper`) the following Perl modules are
  required:

  * [Mojolicious](https://mojolicious.org/) (No, `telegram2mm.pl` is
    no web application, we only use non-web modules from Mojolicious
    like `Mojo::JSON` or `Mojo::File`.)

  * [Archive::Zip](https://metacpan.org/dist/Archive-Zip)

  * [YAML::Tiny](https://metacpan.org/dist/YAML-Tiny)

  * [DateTime](https://metacpan.org/dist/DateTime)

  * [DateTime::TimeZone](https://metacpan.org/dist/DateTime-TimeZone)

  * [DateTime::Format::ISO8601](https://metacpan.org/dist/DateTime-Format-ISO8601)

  * [File::Rename](https://metacpan.org/dist/File-Rename)

* The [Telegram Desktop](https://desktop.telegram.org/) application
  for making the export. Other Telegram clients or the web frontend
  might work, too, but are not tested.

Test Suite
----------

There's a TAP-based test suite in the `t/` subdirectory. You can run
it with e.g. `prove t/*.t` — the tool `prove` comes with Perl.


Author, License and Copyright
-----------------------------

Author: Axel Beckert <axel@ethz.ch>

Copyright 2022 ETH Zurich IT Security Center

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see https://www.gnu.org/licenses/.

See also
--------

* [telegram-to-mattermost](https://git.veone.net/msounkere/telegram-to-mattermost/):
  a similar tool written in Python which I only discovered late in the
  development process. (Looking at the commit messages, the
  development-style is not very convincing with about the 20 last
  commit messages being "Push final version ..." and most other commit
  messages have been used multiple times in a row, too.)

* [whatsapp-mattermost](https://github.com/witchi/whatsapp-mattermost):
  a similar tool written in PHP to import WhatsApp chats into
  Mattermost.
