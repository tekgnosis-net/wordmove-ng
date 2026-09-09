---
title: Introduction
nav_order: 1
permalink: /
---

# wordmove-ng
{: .fs-9 }

Move WordPress sites between environments with one command: files and database, in both directions, over SSH.
{: .fs-6 .fw-300 }

[Install]({{ site.baseurl }}/installation/){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Quick start]({{ site.baseurl }}/quick-start/){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Upgrading from 5.x]({{ site.baseurl }}/upgrading/){: .btn .fs-5 .mb-4 .mb-md-0 }

---

wordmove-ng pushes or pulls the WordPress core, uploads, themes, plugins, mu-plugins, languages and the database between a local install and any number of remote hosts. Files travel with `rsync`; the database is dumped at the source, imported at the target and adapted there with `wp search-replace`, so URLs and paths always match the destination.

It is the maintained, independent successor of [Wordmove](https://github.com/welaika/wordmove) by weLaika, continued through the [kokiddp fork](https://github.com/kokiddp/wordmove). The `movefile.yml` format, the commands and the flags are unchanged; the internals were modernised and a few unsafe behaviours removed. If you come from either project, read [Upgrading from wordmove 5.x]({{ site.baseurl }}/upgrading/).

## How it works

```
                 push  ───────────────▶
   local  ┌────────────┐            ┌────────────┐  remote
          │ wordpress  │   rsync    │ wordpress  │
          │ wp-content │ ─────────▶ │ wp-content │
          │            │ ◀───────── │            │
          │ database   │  dump/scp  │ database   │
          └────────────┘            └────────────┘
                 ◀───────────────  pull
```

- Every remote operation uses the system `ssh`, `scp` and `rsync`. Your ssh-agent, `~/.ssh/config`, jump hosts and modern key types all work exactly as on the command line, and nothing breaks on a new OpenSSL or Ruby release.
- The **source** database is only ever read. Both directions dump the source, import on the target, then run `wp search-replace` on the target. A backup of the target database is taken first.
- Prerequisites on both sides are probed before any backup, dump or import, so a misconfigured host fails before it can do harm. `wordmove-ng doctor` performs the same checks on demand.
- Optional [maintenance mode]({{ site.baseurl }}/database-sync/#maintenance-mode) hides the database replacement from visitors.
- MariaDB and MySQL are both supported, with sandbox-header handling, collation and charset normalisation, socket and port support.
- Runs on Ruby 3.0 through 4.0.

## Where to go next

| I want to… | Read |
| --- | --- |
| install it | [Installation]({{ site.baseurl }}/installation/) |
| sync my first site | [Quick start]({{ site.baseurl }}/quick-start/) |
| move from `wordmove` 5.x | [Upgrading]({{ site.baseurl }}/upgrading/) |
| understand every `movefile.yml` key | [Configuration]({{ site.baseurl }}/configuration/) |
| know what each flag does | [Usage and flags]({{ site.baseurl }}/usage/) |
| know exactly what happens to my database | [Database sync]({{ site.baseurl }}/database-sync/) |
| run commands before or after a deploy | [Hooks]({{ site.baseurl }}/hooks/) |
| fix a problem | [Troubleshooting]({{ site.baseurl }}/troubleshooting/) |

## Credits

Wordmove was created and maintained for a decade by [weLaika](https://dev.welaika.com): Stefano Verna, Ju Liu, Fabrizio Monti, Alessandro Fazzi, Filippo Gangi Dino and [many contributors](https://github.com/welaika/wordmove/graphs/contributors). The workflow, the movefile format and most of the code are theirs. [kokiddp](https://github.com/kokiddp/wordmove) kept it running on modern Ruby, OpenSSL 3 and MariaDB. wordmove-ng is maintained by [tekgnosis.net](https://github.com/tekgnosis-net) under the MIT licence.
