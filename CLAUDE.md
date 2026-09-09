# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

wordmove-ng is a Ruby gem / Thor CLI (executable `wordmove-ng`) that mirrors WordPress installs
(files + database) between a local checkout and remote SSH hosts described in a `movefile.yml`.
It is the independent successor of welaika/wordmove (via the kokiddp fork); the Ruby namespace is
still `Wordmove` and code lives under `lib/wordmove/`. Version lives in `lib/wordmove/version.rb`;
bumping it is a release step, not part of feature work.

## Commands

```bash
bundle install                      # deps (Gemfile.lock is gitignored)
bundle exec rake                    # default task = RSpec suite + rubocop (what CI runs)
bundle exec rake spec               # specs only
bundle exec rspec spec/movefile_spec.rb            # one file
bundle exec rspec spec/movefile_spec.rb:42         # one example by line
bundle exec rspec -e "some example description"    # by description
bundle exec rake rubocop            # lint (rubocop 1.x, NewCops enabled; backlog lives in .rubocop_todo.yml)
bin/wordmove-ng --version           # run the CLI from source without installing
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
   YAML options with CLI options, resolves the environment, then returns `Deployer::SSH`.
   An `ftp` block raises `NoAdapterFound` with a removal message; a leftover
   `global.sql_adapter` key only warns.
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
- **`Deployer::SSH`** (the only deployer): directory sync is rsync via Photocopier; the
  transfer root is always the WordPress root and per-component sync is expressed with
  computed include/exclude path lists, so `exclude` entries in the movefile are always
  relative to the WP root. Remote commands, single-file `scp` transfers, deletes and remote
  hooks go through `Wordmove::SshRunner` (`lib/wordmove/ssh_runner.rb`), which shells out to
  the system `ssh`/`scp` with `BatchMode=yes` unless `ssh.password` is set (then `sshpass`)
  and wraps every remote command in `sh -c`. Do not reintroduce Net::SSH: Photocopier pins
  net-ssh 6, which cannot do RSA SHA-2 auth. `-s/--simulate` becomes `rsync --dry-run` and
  short-circuits DB steps.
- **DB sync** (same class): symmetric in both directions: probe prerequisites on both
  sides, back up the target, dump the source, import on the target, then `wp search-replace`
  for `vhost` and `wordpress_path` *on the target* (locally for pull, over SSH for push),
  optionally inside `wp maintenance-mode`. The source DB is never written. Nothing rewrites
  dump text apart from `normalize_collations!`.
- **`Doctor`** (`lib/wordmove/doctor/*`): `wordmove-ng doctor` validates the movefile schema
  (rejecting `ftp`, reporting prefix collisions), then checks local mysql, wp-cli and rsync,
  and per SSH environment: batch-mode auth, remote prerequisites via `Prerequisites`, and
  gateway-password misuse.
- **`Generators::Movefile`**: `wordmove-ng init` wizard; reads `wp-config.php` and detects the
  local vhost.
- **`Prerequisites`** (`lib/wordmove/prerequisites.rb`): one `sh` probe listing missing
  programs; `DB_SOURCE`/`DB_TARGET`/`REMOTE_ALL` requirement sets shared by deployer and
  doctor.
- **Knobs**: `global.maintenance_mode` (env override `WORDMOVE_MAINTENANCE_MODE`),
  `global.collation_fallbacks`, `global.charset_fallbacks`. Add new toggles as movefile keys
  with an env override and document them in README + CHANGELOG in the same commit.

## Conventions worth knowing

- **Commit messages are Conventional Commits** (`feat:`, `fix:`, `feat!:`/`BREAKING CHANGE:`,
  `docs:`, `chore:`, `ci:`, `test:`, `refactor:`). release-please derives the version bump
  and CHANGELOG from them; never edit `lib/wordmove/version.rb` or `CHANGELOG.md` by hand.
  Releases are published to rubygems.org by `.github/workflows/release.yml` (trusted
  publishing, no secrets).

- Every shell fragment that includes user/config data goes through `Shellwords.escape`
  (or `Shellwords.split` for user-supplied option strings). Secrets must never appear in
  log lines except through `Logger`, which masks `Movefile#secrets`.
- Shell failures are detected via `$CHILD_STATUS.success?` and raised as
  `ShellCommandError`; custom exceptions live in `lib/wordmove/exceptions.rb`.
- `simulate?` must be honoured by every new side-effecting step (log the step, then return).
- Specs stub `Wordmove::SshRunner` (instance_double), `Photocopier::SSH.new` and
  `Prerequisites.missing_*` rather than touching SSH; `spec/deployer/ssh_db_spec.rb` records
  every local and remote command in order and asserts on the sequence.
  Movefile fixtures live in `spec/fixtures/movefiles/`; use `movefile_path_for("name")` from
  `spec/support/fixture_helpers.rb`. `silence_stream` in `spec_helper.rb` quiets noisy output.
- Rubocop limits: 100-col lines, 20-line methods, ABC 40. `rubocop:disable-next` is used
  sparingly around genuinely long orchestration methods (see `Hook.run`).
- The untracked `supertool/` directory is local tooling, not part of the gem.
