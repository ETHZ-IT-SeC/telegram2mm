Import Telegram Group Chat History into a Mattermost Channel
============================================================

Description
-----------

The Perl script `telegram2mm.pl` imports a
[Telegram](https://telegram.org/)
[group](https://telegram.org/faq?setln=en#q-what-39s-the-difference-between-groups-and-channels)
export into a [Mattermost](https://mattermost.com/) channel using
Mattermost's `mmctl import` set of commands.

The tool is currently work in progress and might not yet support all
functionality used on Telegram.

Synopsis
--------

```
./telegram2mm.pl ../import_config.yml ../ChatExport_2022-03-02/result.json
./telegram2mm.pl ../import_config.yml < ../ChatExport_2022-03-02/result.json
cat ../ChatExport_2022-03-02/result.json | ./telegram2mm.pl ../import_config.yml
```


Configuration
-------------

`telegram2mm.pl` expects a [YAML](https://yaml.org/) written configuration file.

### Example configuration file

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
```

The `user<telegram_user_id>` keywords are the values in the `from_id`
JSON field in the chat export file. The value behind them is the user
name (without the `@`) of the according person on the Mattermost
server.

Lines which have a `#` as first non-blank character are comments.

### Chat Export File

The chat export file is what you get when you click on the
per-group-chat menu (top right three dots menu in the [Telegram
Desktop](https://desktop.telegram.org/) app) and click on "Export Chat
History" (or similar depending on localisation) and choose the "JSON"
format.


Example Run
-----------

```
$ ./telegram2mm.pl ../import_config.yml < ../ChatExport_2022-03-02/result.json
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
