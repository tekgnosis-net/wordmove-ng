# Wordmove

![logo](https://raw.githubusercontent.com/welaika/wordmove/master/assets/images/wordmove.png)

This fork keeps Wordmove usable on current Ruby, OpenSSL, MariaDB, and Docker-based WordPress setups while preserving the original workflow and Movefile format.

[![Tests](https://github.com/kokiddp/wordmove/actions/workflows/ruby.yml/badge.svg)](https://github.com/kokiddp/wordmove/actions/workflows/ruby.yml)

## What This Fork Changes

- Runs on modern Ruby versions, including Ruby 3.4 and the current Ruby 4.0 CI line.
- Never opens a Ruby-side SSH session: every remote operation uses the system `ssh`, `scp` and `rsync`, so there is nothing to break on new OpenSSL or Ruby releases.
- Prefers `mariadb` and `mariadb-dump` when available, while still falling back to `mysql` and `mysqldump`.
- Handles MariaDB dump "sandbox mode" headers during import.
- Normalizes unsupported collations and charset declarations in SQL dumps before import.
- Uses `wp-cli` in a Docker-friendly way with `--allow-root`.
- Prints concise command summaries instead of dumping long multi-line shell wrappers to the console.

## Changelog Since `bc9bce6`

- Ruby compatibility:
  - The repo default Ruby is now `3.4.9`.
  - The GitHub Actions matrix now tests `2.6`, `2.7`, `3.0`, `3.1`, `3.2`, `3.3`, `3.4`, and `4.0`.
  - Runtime dependencies were updated for modern Ruby packaging and stdlib extraction: `thor`, `base64`, `bigdecimal`, `mutex_m`, `ed25519`, and `bcrypt_pbkdf`.
  - `Movefile` YAML loading now works across older and newer Psych versions.
  - `bin/console` now falls back to `irb` when `pry` is unavailable on newer Rubies.

- Database sync behavior:
  - Dump commands now auto-detect `mariadb-dump` or `mysqldump`.
  - Import commands now auto-detect `mariadb` or `mysql`.
  - Movefiles can now express unix socket connections with `database.socket`.
  - Legacy `--socket` usage inside `mysql_options` and `mysqldump_options` is still supported.
  - Imports strip the MariaDB sandbox header when present, append a trailing `COMMIT;`, enable `--binary-mode`, disable foreign key checks, and preserve exit status correctly.
  - Existing `mysql_options` are respected without duplicating `--binary-mode`.

- SQL dump normalization:
  - Added built-in collation fallbacks for newer `utf8mb3` collations that older targets may not understand.
  - Added built-in charset fallback from `utf8mb3` to `utf8mb4`.
  - These mappings can be overridden in `movefile.yml`.

- SSH transport and database sync:
  - Remote commands, `scp` transfers and remote hooks now use the system `ssh`/`scp` binaries instead of Net::SSH, so key authentication behaves exactly like rsync (agent, `~/.ssh/config`, RSA SHA-2 signatures). No more surprise password prompts on the DB step.
  - `wordmove push -d` with the `wpcli` adapter now imports on the remote and runs `wp search-replace` there. The local database is never modified during a push; `wp` is required on the remote host instead.
  - `wordmove doctor` tests non interactive SSH authentication and remote `wp` availability for every SSH environment.
  - Hook and Guardian output now masks movefile secrets like the deployer log does.

- WP-CLI and hooks:
  - `wp cli param-dump` now uses `--allow-root`, which avoids failures in root-owned Docker or containerized environments.
  - Hook working directories are now shell-escaped more safely.

- Logging and developer experience:
  - Long generated shell scripts are summarized as meaningful actions such as SQL dump, import, compression, and `wp search-replace`.
  - New specs cover logger summaries.

## Installation

This fork is typically installed directly from GitHub:

```bash
gem install specific_install
gem specific_install https://github.com/kokiddp/wordmove.git
```

For development from a checkout:

```bash
bundle install
bundle exec exe/wordmove --help
```

## Supported Ruby Versions

- Local default in this repository: `3.4.9`
- CI coverage: `2.6`, `2.7`, `3.0`, `3.1`, `3.2`, `3.3`, `3.4`, `4.0`
- Minimum declared Ruby version in the gemspec: `2.6.0`

## Peer Dependencies

Wordmove is orchestration glue. These tools still need to exist in your environment and be available in `$PATH`.

| Program | Mandatory? | Notes |
| --- | --- | --- |
| `rsync` | Yes for SSH protocol | Used for file sync |
| `mysql` or `mariadb` | Yes | Used for DB import and checks |
| `mysqldump` or `mariadb-dump` | Yes | Used for DB export |
| `wp` | Yes by default | Required by the default `wpcli` SQL adapter on the *target* side of a DB sync (see below) |
| `ssh` / `scp` | Yes for SSH protocol | Used for remote commands, single file transfers and remote hooks |
| `sshpass` | Only with `ssh.password` | Feeds the configured password to `ssh`, `scp` and `rsync` |

Remote hosts are also expected to provide `gzip`, `nice`, `rsync`, and either `mysql`/`mariadb` plus `mysqldump`/`mariadb-dump` when database sync happens over SSH. With the default `wpcli` SQL adapter the remote host also needs `wp` in the login shell `$PATH` for `wordmove push -d`.

### SSH authentication

Every SSH operation (rsync, remote commands, `scp` transfers and remote hooks) goes through the system `ssh` client, so your ssh-agent, `~/.ssh/config`, `ProxyJump`/`ssh.gateway` and modern key types all behave exactly as they do on the command line. When no `ssh.password` is configured, connections run with `BatchMode=yes`: a failing key authentication is reported as an error instead of an interactive password prompt. `wordmove doctor` tests non interactive authentication against every SSH environment in your movefile, then checks that `rsync`, `gzip`, `mysql`/`mariadb`, `mysqldump`/`mariadb-dump` and `wp` are available there.

Remote commands are always executed through `sh -c`, so the remote user's login shell can be fish, zsh, csh or anything else. Programs only need to be in the `$PATH` of a non interactive login. `ssh.gateway` is passed as `ssh -J`; a `gateway.password` cannot be used and is ignored (the jump host must accept your key or agent).

### Database sync with the `wpcli` adapter

Both directions follow the same shape: dump the source, import the dump on the target, then run `wp search-replace` on the target for `vhost` and `wordpress_path`. The source database is only ever read.

- `wordmove pull -d`: remote dump, local import, `wp search-replace` locally (requires `wp` locally).
- `wordmove push -d`: local dump, remote import, `wp search-replace` on the remote over SSH (requires `wp` on the remote).

Before touching either database Wordmove probes both sides for the programs the operation needs (`gzip`, `mysqldump`/`mariadb-dump` on the source; `gzip`, `mysql`/`mariadb`, `wp` on the target) and aborts with a list of what is missing, so a misconfigured host never leaves a half-done sync.

Set `global.maintenance_mode: true` (or export `WORDMOVE_MAINTENANCE_MODE=1` for a single run) to wrap the target's import and search-replace in `wp maintenance-mode activate` / `deactivate`, so visitors see WordPress's maintenance page instead of a half-adapted site. Deactivation runs even if the adaptation fails. The default is off.

`wp search-replace` runs with `--all-tables`, so every table in the target database is adapted, including non WordPress tables sharing it. A backup of the target database is downloaded to the local `wp-content/` directory before any import; if the remote adaptation fails after the import, Wordmove logs that backup path so you can restore or re-run the search-replace by hand.

## Quick Start

```bash
wordmove init
wordmove doctor
wordmove pull -e staging -d
wordmove push -e production --all
```

Run `wordmove help` to see all commands and flags.

## `movefile.yml`

Basic example:

```yaml
global:
  sql_adapter: wpcli

local:
  vhost: http://vhost.local
  wordpress_path: /home/john/sites/your_site

  database:
    name: database_name
    user: user
    password: password
    host: localhost

production:
  vhost: https://example.com
  wordpress_path: /var/www/your_site

  database:
    name: database_name
    user: user
    password: password
    host: host
    # port: 3308
    # socket: /path/to/mysql.sock
    # mysqldump_options: --max_allowed_packet=50MB
    # mysql_options: --protocol=TCP

  exclude:
    - ".git/"
    - ".gitignore"
    - "node_modules/"
    - "bin/"
    - "tmp/*"
    - "Gemfile*"
    - "Movefile"
    - "movefile"
    - "movefile.yml"
    - "movefile.yaml"
    - "wp-config.php"
    - "wp-content/*.sql.gz"
    - "*.orig"

  ssh:
    host: host
    user: user
```

Multi-environment Movefiles are still supported. Any first-level key other than `global` and `local` is treated as a remote environment. Use `-e staging`, `-e production`, and so on.

## Environment Variables

Movefiles support ERB, so secrets can be loaded from the shell or from `.env` files.

```yaml
production:
  database:
    user: "<%= ENV['PROD_DB_USER'] %>"
    password: "<%= ENV['PROD_DB_PASS'] %>"
```

You can populate those variables either in the shell:

```bash
export PROD_DB_USER="username"
export PROD_DB_PASS="password"
```

or in a `.env` file next to the Movefile:

```bash
PROD_DB_USER="username"
PROD_DB_PASS="password"
```

## SQL Import and Dump Compatibility

This fork changes DB import/export behavior in a few important ways:

- MariaDB client binaries are preferred automatically when present.
- You can now configure unix socket connections directly as `database.socket: /path/to/mysqld.sock`.
- The older `--socket ...` form inside `database.mysql_options` or `database.mysqldump_options` still works and remains backward-compatible.
- Dumps beginning with:

```sql
/*!999999- enable the sandbox mode */
```

  are imported correctly by stripping that header before the actual import.
- Imports append a final `COMMIT;` to reduce partial transaction edge cases.
- Imports enable `SET FOREIGN_KEY_CHECKS=0` and `--binary-mode` unless you already configured binary mode explicitly.

These changes are especially useful when moving databases between Local, Docker, MariaDB 11+, and older shared-hosting MySQL servers.

Example:

```yaml
local:
  database:
    name: local
    user: root
    password: root
    host: localhost
    socket: /home/koki/.config/Local/run/eZGRlahhA/mysql/mysqld.sock
```

When `wordmove init` reads a `wp-config.php` entry like:

```php
define('DB_HOST', 'localhost:/home/koki/.config/Local/run/eZGRlahhA/mysql/mysqld.sock');
```

it now generates separate `host` and `socket` fields in the Movefile instead of leaving the combined value inside `host`.

Likewise, when `DB_HOST` contains a custom port such as:

```php
define('DB_HOST', 'localhost:3307');
```

`wordmove init` now generates separate `host` and `port` fields and uncomments the local `port` line in the generated Movefile.

## Collation Fallbacks

If your source dump contains collations unsupported by the destination server, Wordmove can rewrite them before import.

Default behavior already normalizes newer `utf8mb3` collations such as:

- `utf8mb3_uca1400_ai_ci`
- `utf8mb3_uca1400_as_cs`
- `utf8mb3_unicode_520_ci`

to `utf8mb4_unicode_ci`, and upgrades `utf8mb3` to `utf8mb4`.

You can override the defaults in `movefile.yml`:

```yaml
global:
  collation_fallbacks:
    utf8mb3_uca1400_ai_ci: utf8mb4_unicode_ci
    utf8mb3_uca1400_as_cs: utf8mb4_unicode_ci

  charset_fallbacks:
    utf8mb3: utf8mb4
```

## Docker and Root-Owned WordPress Installs

The default `wpcli` adapter now calls `wp cli param-dump --allow-root --with-values`, which makes path discovery and search-replace flows work better in containerized environments where `wp` runs as `root`.

## Logging

Long generated shell wrappers are summarized into shorter, more useful task lines. For example, instead of printing the full multi-line SQL import script, Wordmove now logs intent-oriented summaries such as:

- `dump database my_db to ./wp-content/dump.sql`
- `compress ./wp-content/dump.sql`
- `wp search-replace old.example.test -> new.example.test in ./public`
- `import SQL dump ./wp-content/dump.sql into database local (strip sandbox header, append COMMIT)`

This keeps normal output readable without hiding what Wordmove is actually doing.

## Usage Notes

### Mirroring

File push and pull operations mirror the source. Files missing from the source can be deleted on the destination. Exclude anything you need to preserve.

### SSH

- `rsync` must be installed locally.
- SSH public key authentication is still the recommended setup.
- Passwords inside `movefile.yml` may still work, but key-based auth is strongly preferred.

### FTP and SFTP

FTP and SFTP support was removed in wordmove-ng 6.0. It only ever existed for shell-less shared hosts, where the database had to be handled by uploading temporary PHP scripts and URLs had to be rewritten in the dump text with a regex. A movefile with an `ftp` block now fails with a clear error. If you still need an FTP-only host, keep using the legacy `wordmove` 5.x gem for it.

## Upstream Documentation

Most of the original Wordmove workflow and Movefile format still match the upstream documentation:

- [Usage and flags explained](https://github.com/welaika/wordmove/wiki/Usage-and-flags-explained)
- [Multiple environments explained](https://github.com/welaika/wordmove/wiki/Multiple-environments-explained)
- [Movefile configuration explained](https://github.com/welaika/wordmove/wiki/movefile.yml-configurations-explained)
- [Hooks](https://github.com/welaika/wordmove/wiki/Hooks)

Where this README and the upstream wiki disagree, this README describes the behavior of this fork.

## Contributing

```bash
bundle exec rspec
```

The project CI currently runs the suite across:

- `2.6`
- `2.7`
- `3.0`
- `3.1`
- `3.2`
- `3.3`
- `3.4`
- `4.0`

Please keep the README updated when changing user-facing behavior, installation steps, supported versions, or command output.

## Credits

- The dump script is based on the [`MYSQL-dump` PHP package](https://github.com/dg/MySQL-dump) by David Grudl.
- The import script uses the [BigDump](http://www.ozerov.de/bigdump/) library.
- Original project by [weLaika](https://dev.welaika.com).
