# wordmove-ng

![logo](assets/images/wordmove-ng.png)

wordmove-ng moves WordPress sites between environments. One command pushes or pulls
the core, uploads, themes, plugins, mu-plugins, languages and the database between a
local install and any number of remote hosts over SSH, rewriting URLs and paths on the
target with wp-cli.

It is the maintained, independent successor of [Wordmove](https://github.com/welaika/wordmove)
by weLaika, continued through the [kokiddp fork](https://github.com/kokiddp/wordmove).
The movefile format, commands and flags are unchanged. What changed is under the hood, and
in a few places where the old behaviour was unsafe. See [Upgrading from wordmove 5.x](#upgrading-from-wordmove-5x).

[![Tests](https://github.com/tekgnosis-net/wordmove-ng/actions/workflows/ruby.yml/badge.svg)](https://github.com/tekgnosis-net/wordmove-ng/actions/workflows/ruby.yml)

## Highlights

- **No Ruby-side SSH.** Every remote operation goes through the system `ssh`, `scp` and
  `rsync`, so your agent, `~/.ssh/config`, jump hosts and modern key types all just work,
  and nothing breaks on a new OpenSSL or Ruby.
- **The source database is never written.** Push and pull both dump the source, import on
  the target and run `wp search-replace` on the target.
- **Fails before it breaks anything.** Prerequisites on both sides are probed before any
  backup, dump or import. `wordmove-ng doctor` checks SSH authentication and remote programs
  per environment.
- **Optional maintenance mode** around the target's database replacement.
- MariaDB first (`mariadb`, `mariadb-dump`) with MySQL fallback, sandbox-header handling,
  collation and charset normalisation, socket and port support.
- Runs on Ruby 3.0 through 4.0.

## Installation

Ruby 3.0 or newer is required.

```bash
gem install wordmove-ng
```

Until the gem is on rubygems.org, or to run the latest master:

```bash
gem install specific_install
gem specific_install https://github.com/tekgnosis-net/wordmove-ng.git
```

From a checkout:

```bash
bundle install
bin/wordmove-ng --help
```

## Quick start

```bash
cd /path/to/your/wordpress   # where wp-config.php lives
wordmove-ng init             # writes movefile.yml, pre-filled from wp-config.php
wordmove-ng doctor           # validates movefile.yml, local tools, SSH auth, remote tools
wordmove-ng pull -e staging --all
wordmove-ng push -e production -t -p   # themes and plugins only
wordmove-ng push -e production -d -s   # simulate a database push
```

Run `wordmove-ng help` for all commands and `wordmove-ng help push` for the flags.
Component flags: `-w` core, `-u` uploads, `-t` themes, `-p` plugins, `-m` mu-plugins,
`-l` languages, `-d` database, `--all` everything (`--all --no-uploads` to exclude one).
`-s` simulates, `-e` picks the environment, `-c` points at another movefile.

## Peer dependencies

wordmove-ng is orchestration glue around standard tools.

**Locally**

| Program | Needed for |
| --- | --- |
| `ssh`, `scp`, `rsync` | every remote operation |
| `sshpass` | only when `ssh.password` is set in the movefile |
| `gzip` | database sync |
| `mysqldump` or `mariadb-dump` | `push -d` (dumping the local database) |
| `mysql` or `mariadb` | `pull -d` (importing into the local database) and `doctor` |
| `wp` ([WP-CLI](https://wp-cli.org)) | `pull -d` (adapting the local database) |

**On each remote**, in the `$PATH` of a non interactive login

| Program | Needed for |
| --- | --- |
| `rsync`, `gzip` | file and database sync |
| `mysqldump` or `mariadb-dump` | `pull -d` |
| `mysql` or `mariadb`, `wp` | `push -d` |

`wordmove-ng doctor` reports exactly what is missing where, and every database operation
re-checks before doing anything.

## SSH authentication

Everything uses the system `ssh` client. When no `ssh.password` is configured, connections run
with `BatchMode=yes`: a failing key authentication is reported as an error with the exact
command that failed, never an interactive password prompt.

- `ssh.host`, `ssh.user`, `ssh.port` map to the obvious ssh options. A host configured in
  `~/.ssh/config` works with only `ssh.host` set.
- `ssh.password` is passed through `sshpass` to `ssh`, `scp` and `rsync`. Keys are strongly
  preferred.
- `ssh.gateway` becomes `ssh -J`. The jump host must accept your key or agent; a
  `gateway.password` cannot be honoured and is ignored (doctor warns).
- `ssh.rsync_options` are appended to the rsync command.

Remote commands always run through `sh -c`, so the remote login shell may be bash, zsh,
fish or csh.

## Database sync

Both directions have the same shape: dump the source, import the dump on the target, run
`wp search-replace` on the target for `vhost` and `wordpress_path`. The source database is
only ever read.

- `wordmove-ng pull -d`: back up the local database, dump the remote, import locally,
  search-replace locally.
- `wordmove-ng push -d`: back up the remote database, dump locally, import on the remote,
  search-replace on the remote over SSH.

Backups are written to the local `wp-content/` directory as timestamped `.sql.gz` files
before any import. If the remote adaptation fails after the import, the log names the
backup to restore from.

`wp search-replace` runs with `--all-tables --skip-columns=guid`, so every table in the
target database is adapted, including non WordPress tables sharing it, and post GUIDs are
left alone as WordPress recommends. `--no-adapt` skips the search-replace entirely.

If one of the four search terms is a prefix of another (for example a local vhost of
`https://site.test` and a remote of `https://site.test.example.com`) the shorter replacement
also rewrites the longer value. Doctor reports this as an error and the DB step warns.

### Maintenance mode

```yaml
global:
  maintenance_mode: true
```

wraps the target's import and search-replace in `wp maintenance-mode activate` and
`deactivate`, so visitors see the WordPress maintenance page rather than a site pointing at
the other environment's URLs for a few seconds. Deactivation runs even when the adaptation
fails. `WORDMOVE_MAINTENANCE_MODE=1` forces it on for a single run. Default: off.

### MariaDB and MySQL compatibility

- `mariadb` and `mariadb-dump` are preferred when present, falling back to `mysql` and
  `mysqldump`.
- Dumps starting with the MariaDB sandbox header (`/*!999999- enable the sandbox mode */`)
  import cleanly on older servers.
- Imports run with `--binary-mode`, `SET FOREIGN_KEY_CHECKS=0` and a trailing `COMMIT;`,
  unless `mysql_options` already sets binary mode.
- `database.socket` and `database.port` are first-class; `--socket` inside
  `mysql_options` or `mysqldump_options` still works.
- Newer `utf8mb3` collations are rewritten to `utf8mb4_unicode_ci` and `utf8mb3` to
  `utf8mb4` before import. Override or extend the mappings:

```yaml
global:
  collation_fallbacks:
    utf8mb3_uca1400_ai_ci: utf8mb4_unicode_ci
  charset_fallbacks:
    utf8mb3: utf8mb4
```

- `wp` is always called with `--allow-root`, so root-owned Docker installs work.

## `movefile.yml`

```yaml
global:
  maintenance_mode: false

local:
  vhost: http://vhost.local
  wordpress_path: /home/john/sites/your_site

  database:
    name: database_name
    user: user
    password: password
    host: localhost
    # port: 3306
    # socket: /path/to/mysql.sock

production:
  vhost: https://example.com
  wordpress_path: /var/www/your_site

  database:
    name: database_name
    user: user
    password: password
    host: host
    # mysqldump_options: --max_allowed_packet=50MB
    # mysql_options: --protocol=TCP

  exclude:
    - ".git/"
    - ".env"
    - "node_modules/"
    - "wp-config.php"
    - "wp-content/*.sql.gz"

  ssh:
    host: host
    user: user
    # port: 22
    # password: only with sshpass installed; prefer keys
    # rsync_options: --verbose
    # gateway:
    #   host: bastion.example.com
    #   user: jump

  # forbid:
  #   push:
  #     db: true          # never push the database to production
  # hooks:
  #   push:
  #     before:
  #       - command: echo "about to push"
  #         where: local
  #     after:
  #       - command: wp cache flush
  #         where: remote
  #         raise: false
```

Every first-level key other than `global` and `local` is a remote environment; pick one with
`-e`. `movefile.yml` is evaluated as ERB, so secrets can come from the environment or from
a `.env` / `.env.<environment>` file next to it:

```yaml
production:
  database:
    password: "<%= ENV['PROD_DB_PASS'] %>"
```

File sync mirrors the source: files missing on the source are deleted on the destination.
Put anything you need to keep in `exclude`, which is always relative to `wordpress_path`.

The wiki has the full reference:
[movefile.yml configurations explained](https://github.com/tekgnosis-net/wordmove-ng/wiki/movefile.yml-configurations-explained),
[Usage and flags explained](https://github.com/tekgnosis-net/wordmove-ng/wiki/Usage-and-flags-explained),
[Multiple environments explained](https://github.com/tekgnosis-net/wordmove-ng/wiki/Multiple-environments-explained),
[Hooks](https://github.com/tekgnosis-net/wordmove-ng/wiki/Hooks).
Where a wiki page still describes wordmove 5.x behaviour, this README wins.

## Logging

Long generated shell scripts are summarised into intent lines such as
`dump database my_db to ./wp-content/dump.sql`, `compress ./wp-content/dump.sql`,
`wp search-replace old.test -> new.test in /var/www/site` and
`import SQL dump ... (strip sandbox header, append COMMIT)`. Passwords, hosts, vhosts and
paths from the movefile are masked as `[secret]` in all output, including hook output.

## Upgrading from wordmove 5.x

This applies to both the original `wordmove` gem and the kokiddp fork. Your `movefile.yml`
keeps working with the exceptions below.

1. **Install the new gem and use the new command.** `gem install wordmove-ng`, then call
   `wordmove-ng` instead of `wordmove`. Both gems can stay installed side by side.
2. **Ruby 3.0 or newer.** Ruby 2.6 and 2.7 are no longer supported.
3. **Put `wp` on your remotes.** `push -d` now adapts the database on the remote, so WP-CLI
   must be installed there and be in the `$PATH` of a non interactive login. It is a single
   PHAR file: [installing WP-CLI](https://wp-cli.org/#installing). Run `wordmove-ng doctor`
   to confirm.
4. **FTP and SFTP are gone.** A movefile with an `ftp` block fails with a clear error. FTP
   only ever existed for shell-less shared hosts, where the database had to be handled by
   uploading temporary PHP scripts and URLs were rewritten in the dump with a regex. Keep the
   legacy `wordmove` 5.x gem for such hosts, or move them to SSH.
5. **`global.sql_adapter` is ignored.** URL and path adaptation always uses wp-cli on the
   target. The key is still accepted, with a warning, so old movefiles validate; remove it
   when convenient. `database.charset` (removed in 3.0) is no longer accepted by the schema.
6. **Push no longer touches your local database.** Old versions ran `wp search-replace`
   on the live local database during a push and restored it afterwards, which left the local
   site pointing at production if anything failed in between. That is gone.
7. **SSH behaves like rsync did.** If rsync worked but the database step asked for a
   password, the cause was the old Net::SSH library, which could not sign RSA keys with
   SHA-2. That path no longer exists. If key authentication fails now, you get an error with
   the failing `ssh` command instead of a prompt. `ssh.gateway.password` is ignored.
8. **Remote programs are checked up front.** Missing `gzip`, `mysql`, `mysqldump` or `wp`
   on either side aborts before any backup or dump, listing what is missing.
9. **New, optional:** `global.maintenance_mode` (see above).

## Contributing

```bash
bundle install
bundle exec rake          # specs + rubocop, what CI runs
bundle exec rspec spec/deployer/ssh_db_spec.rb   # one file
```

CI runs on Ruby 3.0, 3.1, 3.2, 3.3, 3.4 and 4.0. Please keep this README updated when
changing user-facing behaviour, and write [Conventional Commits](https://www.conventionalcommits.org)
(`feat:`, `fix:`, `feat!:` for breaking changes): the changelog and version number are
generated from them. See [CONTRIBUTING.md](CONTRIBUTING.md).

### Releasing

Releases are automated by [release-please](https://github.com/googleapis/release-please)
and published to [rubygems.org](https://rubygems.org/gems/wordmove-ng) with
[trusted publishing](https://guides.rubygems.org/trusted-publishing/), so no API key is
stored anywhere.

1. Every push to `master` updates a "release PR" that bumps `lib/wordmove/version.rb` and
   `CHANGELOG.md` according to the commits since the last release.
2. Merging that PR creates the `vX.Y.Z` tag and the GitHub release.
3. The `publish` job in `.github/workflows/release.yml` then runs the test suite on the
   tagged commit, builds the gem, pushes it to rubygems.org and attaches the `.gem` file to
   the GitHub release.

Pushing a `v*` tag by hand at the head of `master` triggers the same publish job; that is
how 6.0.0 is cut.

One-time setup for a new maintainer or a fork:

- On rubygems.org, under your profile's *Trusted publishers*, add a **pending** publisher
  for gem `wordmove-ng`, repository owner `tekgnosis-net`, repository `wordmove-ng`,
  workflow `release.yml`, environment `release`. It becomes a regular publisher, and you
  the gem owner, after the first push.
- In the GitHub repository settings create an environment named `release`, and under
  *Actions → General* enable "Allow GitHub Actions to create and approve pull requests"
  so release-please can open its PR.

## Credits and licence

- Wordmove was created and maintained for a decade by [weLaika](https://dev.welaika.com):
  Stefano Verna, Ju Liu, Fabrizio Monti, Alessandro Fazzi, Filippo Gangi Dino and
  [many contributors](https://github.com/welaika/wordmove/graphs/contributors). The
  workflow, movefile format and most of the code are theirs.
- [kokiddp](https://github.com/kokiddp/wordmove) kept it running on modern Ruby, OpenSSL 3
  and MariaDB and added socket, collation and Docker support.
- wordmove-ng is maintained by [tekgnosis.net](https://github.com/tekgnosis-net).

MIT licence, see [LICENSE](LICENSE).
