# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Wordmove is a Ruby gem / Thor CLI that mirrors WordPress installs (files + database) between a
local checkout and remote hosts described in a `movefile.yml`. This repo is a fork
(`origin` = tekgnosis-net/wordmove, `upstream` = kokiddp/wordmove, original = welaika/wordmove).
Version lives in `lib/wordmove/version.rb`; bumping it is a maintainer/release step, not part of
feature work.

## Commands

```bash
bundle install                      # deps (Gemfile.lock is gitignored)
bundle exec rake                    # default task = RSpec suite + rubocop (what CI runs)
bundle exec rake spec               # specs only
bundle exec rspec spec/movefile_spec.rb            # one file
bundle exec rspec spec/movefile_spec.rb:42         # one example by line
bundle exec rspec -e "some example description"    # by description
bundle exec rake rubocop            # lint (rubocop 1.x, NewCops enabled; backlog lives in .rubocop_todo.yml)
bin/wordmove --version              # run the CLI from source without installing
rake install                        # build + install the gem locally
```

- `.rspec` already sets `--require spec_helper --color`; documentation formatter and
  SimpleCov are enabled in `spec/spec_helper.rb`.
- CI (`.github/workflows/ruby.yml`) runs `bundle exec rake` on Ruby 3.0 through 4.0. Code must
  run on Ruby 3.0 **and** Ruby 4 (see the `StringScanner#peep` shim in `lib/wordmove.rb` and the
  explicit `ostruct`/`base64`/`mutex_m`/`logger` runtime deps in the gemspec). Local
  `.ruby-version` is 3.4.9. Dev dependencies live in the Gemfile, not the gemspec.
- Fix new rubocop offences rather than adding to `.rubocop_todo.yml`; the todo file only
  grandfathers the pre-6.0 backlog.
- `pry-byebug` is loaded optionally in specs; a `LoadError` there is tolerated.

## Architecture (request flow)

`exe/wordmove` -> `Wordmove::CLI` (Thor, `lib/wordmove/cli.rb`) -> for `push`/`pull`:

1. `Deployer::Base.deployer_for(cli_options)` builds a `Movefile`, loads dotenv, merges the
   YAML options with CLI options, resolves the environment, then returns **one of three**
   concrete classes: `Deployer::FTP`, `Deployer::Ssh::WpcliSqlAdapter`, or
   `Deployer::Ssh::DefaultSqlAdapter` (SSH subclass chosen by `global.sql_adapter`, default
   `wpcli`). Anything else raises `NoAdapterFound`.
2. `Hook.run(action, :before, options)` runs local/remote hooks from the movefile.
3. `Guardian#allows(task)` checks `<env>.forbid.<push|pull>.<task>`; forbidden tasks are
   logged and skipped, not raised.
4. For each selected task (`wordpress uploads themes plugins mu_plugins languages db`) the CLI
   calls `deployer.send("push_#{task}")` / `pull_…`. `--all` selects every task unless a flag is
   explicitly `false`.
5. `Hook.run(action, :after, options)`.

Key pieces:

- **`Movefile`** (`lib/wordmove/movefile.rb`): finds `{M,m}ovefile{,.yml,.yaml}` walking up
  until `/` or a dir containing `wp-config.php`; evaluates ERB then `YAML.safe_load`; owns
  environment selection (`-e` required when more than one remote env) and `secrets` (passwords,
  hosts, vhosts, wordpress paths) that `Logger` masks in all output. Doctor validates it with
  Kwalify against the three schemas in `lib/wordmove/assets/`.
- **`Deployer::Base`**: shared logic. Task methods and `local_/remote_<type>_dir` helpers are
  metaprogrammed from lists; add a component by extending those lists plus the CLI's
  `wordpress_options` and `WordpressDirectory::Path`. Builds `mysqldump`/`mysql` commands
  (prefers `mariadb-dump`/`mariadb` when present), `Shellwords.escape`s every arg, and
  rewrites `utf8mb3*` collations/charsets in dumps via `normalize_collations!`
  (overridable through `global.collation_fallbacks` / `global.charset_fallbacks`).
- **`Deployer::SSH`**: directory sync is rsync via Photocopier; the transfer root is always
  the WordPress root and per-component sync is expressed with computed include/exclude path
  lists, so `exclude` entries in the movefile are always relative to the WP root. Remote
  commands, single-file `scp` transfers, deletes and remote hooks go through
  `Wordmove::SshRunner` (`lib/wordmove/ssh_runner.rb`), which shells out to the system
  `ssh`/`scp` with `BatchMode=yes` unless `ssh.password` is set (then `sshpass`). Do not
  reintroduce Net::SSH for these: Photocopier pins net-ssh 6, which cannot do RSA SHA-2 auth.
  `-s/--simulate` becomes `rsync --dry-run` and short-circuits DB steps.
- **DB sync (`Ssh::WpcliSqlAdapter`)**: symmetric in both directions: backup the target,
  dump the source, import on the target, then `wp search-replace` for `vhost` and
  `wordpress_path` *on the target* (locally for pull, over SSH for push). The source DB is
  never written. `check_*_db_prerequisites!` verifies `wp` on the target before any side
  effect. `Ssh::DefaultSqlAdapter` instead rewrites the dump text with `SqlAdapter::Default`
  (regex-based, weaker with nested serialized data).
- **`Deployer::FTP`**: legacy path. Uploads one-time-password, self-deleting PHP scripts
  rendered from `assets/dump.php.erb` / `import.php.erb` and drives them over HTTP. No remote
  hooks. `--debug` keeps the output file.
- **`Doctor`** (`lib/wordmove/doctor/*`): `wordmove doctor` checks movefile schema, ssh,
  rsync, mysql, wp-cli.
- **`Generators::Movefile`**: `wordmove init` wizard; reads `wp-config.php` and detects the
  local vhost.

## Conventions worth knowing

- Every shell fragment that includes user/config data goes through `Shellwords.escape`
  (or `Shellwords.split` for user-supplied option strings). Secrets must never appear in
  log lines except through `Logger`, which masks `Movefile#secrets`.
- Shell failures are detected via `$CHILD_STATUS.success?` and raised as
  `ShellCommandError`; custom exceptions live in `lib/wordmove/exceptions.rb`.
- `simulate?` must be honoured by every new side-effecting step (log the step, then return).
- Specs mock `Deployer::Base.deployer_for` / Photocopier rather than touching SSH/FTP.
  Movefile fixtures live in `spec/fixtures/movefiles/`; use `movefile_path_for("name")` from
  `spec/support/fixture_helpers.rb`. `silence_stream` in `spec_helper.rb` quiets noisy output.
- Rubocop limits: 100-col lines, 20-line methods, ABC 40. Disable/enable comments are used
  sparingly around genuinely long orchestration methods (see `Hook.run`).
- The untracked `supertool/` directory is local tooling, not part of the gem.
