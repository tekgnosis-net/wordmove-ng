# Changelog

All notable changes to wordmove-ng are documented here. The project follows
[Semantic Versioning](https://semver.org). Releases of the original Wordmove (up to 5.2.2)
are listed at https://github.com/welaika/wordmove/releases; the kokiddp fork's changes
between 5.2.2 and this project are summarised under 6.0.0.

## 6.0.0 (2026-09-09)

First release as an independent project. Breaking changes are marked **breaking**.

### Identity

- **breaking** Gem renamed to `wordmove-ng`, executable renamed to `wordmove-ng`. The Ruby
  namespace stays `Wordmove`. The legacy `wordmove` gem can remain installed alongside.
- **breaking** Ruby 3.0 or newer is required. CI covers 3.0 through 4.0.
- New logo based on the original emblem and wordmark with an "ng" badge.

### SSH transport

- Remote commands, single-file transfers, deletes and remote hooks use the system `ssh` and
  `scp` binaries (`Wordmove::SshRunner`) instead of Net::SSH. Key authentication now behaves
  exactly like the rsync file sync: ssh-agent, `~/.ssh/config`, RSA SHA-2 signatures and
  `ProxyJump` all work. Fixes the database step prompting for a password while rsync
  succeeded, caused by net-ssh 6 lacking RSA SHA-2 client authentication.
- Connections run with `BatchMode=yes` unless `ssh.password` is set (then `sshpass`). A
  failed key authentication is an error with the failing command, never a prompt.
- `ssh.gateway` is passed as `ssh -J`. `gateway.password` cannot be honoured and is ignored;
  doctor warns about it.
- Remote commands run through `sh -c`, so non-POSIX remote login shells (fish, csh) work.
- Removed the net-ssh OpenSSL 3 compatibility shim and the `ed25519` and `bcrypt_pbkdf`
  dependencies, which are no longer needed.

### Database sync

- **breaking** `push -d` imports the dump on the remote and runs `wp search-replace` there.
  The local database is never modified during a push. WP-CLI is required on the remote.
- **breaking** FTP and SFTP support removed, together with the PHP dump/import scripts and
  the regex-based dump rewriter (`sql_adapter: default`). A movefile with an `ftp` block
  raises a clear error.
- `global.sql_adapter` is ignored (accepted with a warning). The `global` section is now
  optional. `database.charset` removed from the schema.
- Prerequisites (`gzip`, `mysql`/`mariadb`, `mysqldump`/`mariadb-dump`, `wp`) are probed on
  both sides before any backup or dump; a missing program aborts with a list.
- New `global.maintenance_mode` (or `WORDMOVE_MAINTENANCE_MODE=1`) wraps the target's
  import and search-replace in `wp maintenance-mode activate`/`deactivate`, deactivating
  even on failure. Default off.
- Warns when one search-replace term is a prefix of another; doctor reports it as an error.
- If the remote adaptation fails after the import, the log names the pre-import backup.
- Collations are normalised once per dump (previously twice on push).

### Doctor

- Tests non interactive SSH authentication for every SSH environment and prints the failing
  command and stderr.
- Probes each remote for `rsync`, `gzip`, `mysql`/`mariadb`, `mysqldump`/`mariadb-dump` and
  `wp`.
- Reports `ftp` blocks, prefix collisions and gateway passwords.

### Other

- `--result-file` and gzip paths are shell-escaped with Shellwords (a `"` or `$` in
  `wordpress_path` no longer breaks the dump or import).
- Hook and Guardian output mask movefile secrets like the deployer log.
- Simulate mode no longer appends `--dry-run` to the shared `rsync_options` string.
- Rubocop 1.x with the pre-existing backlog grandfathered in `.rubocop_todo.yml`; the default
  rake task runs specs and rubocop. Development dependencies moved to the Gemfile.

### Inherited from the kokiddp fork (unreleased upstream changes since wordmove 5.2.2)

- Ruby 3.x and 4.0 compatibility, stdlib gems declared explicitly.
- MariaDB binaries preferred, sandbox-header stripping, `--binary-mode`,
  `SET FOREIGN_KEY_CHECKS=0` and trailing `COMMIT;` on import.
- `database.socket` and `database.port`; `init` splits `DB_HOST` values with a socket or port.
- Built-in `utf8mb3` collation and charset fallbacks, overridable in the movefile.
- `wp` called with `--allow-root`; local vhost detected from `wp-config.php` or `wp option`.
- Command summaries in the log instead of full shell scripts; secrets masked.
- Paths with spaces supported throughout.
