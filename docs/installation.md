---
title: Installation
nav_order: 2
---

# Installation
{: .no_toc }

1. TOC
{:toc}

## Ruby

wordmove-ng needs **Ruby 3.0 or newer** and is tested on 3.0 through 4.0. Check what you have:

```bash
ruby --version
```

If that prints 3.0 or newer you can skip to [the gem](#the-gem). Otherwise pick one of the routes below. A version manager is the usual choice: it leaves the system Ruby alone (several distributions depend on it), installs gems into your home directory without `sudo`, and lets you upgrade Ruby later without touching anything else. Any current 3.x works; `3.4` is a good default and is what the project itself uses.

### Option A: your distribution's Ruby
{: .no_toc }

The quickest route when the packaged version is recent enough. Debian 12, Ubuntu 22.04 and later, Fedora and Arch all ship Ruby 3.x.

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y ruby-full build-essential
# Fedora
sudo dnf install -y ruby ruby-devel @development-tools
# Arch
sudo pacman -S ruby base-devel
```

Then install the gem for your user only, so no `sudo` is needed and the system stays untouched:

```bash
gem install --user-install wordmove-ng
```

`--user-install` puts executables under `~/.local/share/gem/ruby/<version>/bin` (older Rubies: `~/.gem/ruby/<version>/bin`). Add that directory to your `PATH` in `~/.bashrc` or `~/.zshrc`; `gem env` prints the exact path under `USER INSTALLATION DIRECTORY`.

### Option B: rbenv
{: .no_toc }

Lightweight, shell-agnostic, and packaged everywhere. `rbenv` selects a Ruby; the `ruby-build` plugin compiles one.

```bash
# macOS
brew install rbenv ruby-build
# Debian / Ubuntu (rbenv from apt is often old; the git checkout below is current)
sudo apt install -y git build-essential autoconf libssl-dev libyaml-dev zlib1g-dev libffi-dev libgmp-dev rustc
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
~/.rbenv/bin/rbenv init      # prints the line to add to your shell profile; add it, then reopen the terminal
```

```bash
rbenv install 3.4.11         # compiles Ruby, takes a few minutes
rbenv global 3.4.11
ruby --version
gem install wordmove-ng
rbenv rehash                 # makes the wordmove-ng executable visible
```

`rbenv install --list` shows the versions available; run `git -C ~/.rbenv/plugins/ruby-build pull` (or `brew upgrade ruby-build`) if a recent one is missing.

### Option C: RVM
{: .no_toc }

Heavier than rbenv but familiar to many WordPress developers, and its gemsets isolate one project's gems from another's.

```bash
gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
\curl -sSL https://get.rvm.io | bash -s stable
source ~/.rvm/scripts/rvm    # or reopen the terminal
```

```bash
rvm install 3.4.11
rvm use 3.4.11 --default
gem install wordmove-ng
```

RVM installs the build dependencies for you (it may ask for your `sudo` password once). To keep wordmove-ng in its own gemset: `rvm gemset create wordmove && rvm use 3.4.11@wordmove --default` before `gem install`. If you use the [cron script]({{ site.baseurl }}/automation/), set `RUBY_VERSION` to the same `ruby-3.4.11` or `ruby-3.4.11@wordmove` string.

### Option D: mise
{: .no_toc }

One tool for Ruby, Node, PHP and more, with a single config file per project. Good if you already manage other runtimes with it.

```bash
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc   # or: mise activate zsh >> ~/.zshrc
exec $SHELL
```

```bash
mise use --global ruby@3.4
ruby --version
gem install wordmove-ng
```

mise compiles Ruby through ruby-build as well, so on Linux install the same build packages listed under rbenv first; on macOS `brew install openssl@3 readline libyaml gmp autoconf`.

### Docker
{: .no_toc }

If you would rather not install Ruby at all, run wordmove-ng from the official Ruby image. Mount your site and your SSH configuration, and make sure the peer tools are installed in the container:

```bash
docker run --rm -it \
  -v "$PWD":/site -w /site \
  -v "$HOME/.ssh":/root/.ssh:ro \
  ruby:3.4 bash -c 'apt-get update -qq && apt-get install -y -qq rsync openssh-client mariadb-client >/dev/null \
    && gem install -q wordmove-ng && wordmove-ng doctor'
```

For repeated use bake that into a small Dockerfile. Note that `local` in your movefile then means "inside the container": `wordpress_path` is `/site`, and the local database must be reachable from the container (`host: host.docker.internal` on Docker Desktop, or the compose service name).

### Checking the result
{: .no_toc }

```bash
ruby --version        # 3.0 or newer
gem --version
wordmove-ng --version
```

If `wordmove-ng` is not found right after installing, the executable directory is not in your `PATH` yet: open a new terminal, and for rbenv run `rbenv rehash`. `gem env` shows where executables were placed.

## The gem

```bash
gem install wordmove-ng
wordmove-ng --version
```

To run the latest `master` instead of a release:

```bash
gem install specific_install
gem specific_install https://github.com/tekgnosis-net/wordmove-ng.git
```

From a checkout, for development:

```bash
git clone https://github.com/tekgnosis-net/wordmove-ng.git
cd wordmove-ng
bundle install
bin/wordmove-ng --help
```

The legacy `wordmove` 5.x gem can stay installed alongside: the executables have different names.

## Peer dependencies

wordmove-ng is orchestration glue around standard tools. `wordmove-ng doctor` reports exactly what is missing on which side, and every database operation re-checks before doing anything.

### Locally

| Program | Needed for |
| --- | --- |
| `ssh`, `scp`, `rsync` | every remote operation |
| `sshpass` | only when `ssh.password` is set in the movefile |
| `gzip` | database sync |
| `mysqldump` or `mariadb-dump` | `push -d` (dumping the local database) |
| `mysql` or `mariadb` | `pull -d` (importing into the local database) and `doctor` |
| `wp` ([WP-CLI](https://wp-cli.org)) | `pull -d` (adapting the local database) |

### On each remote

In the `$PATH` of a **non interactive** login. Check with `ssh host 'echo $PATH'`.

| Program | Needed for |
| --- | --- |
| `rsync`, `gzip` | file and database sync |
| `mysqldump` or `mariadb-dump` | `pull -d` |
| `mysql` or `mariadb`, `wp` | `push -d` |

WP-CLI is a single PHAR file. If your host does not ship it, put it in `~/bin` and add that directory to `PATH` in `~/.bashrc` or `~/.profile`: [installing WP-CLI](https://wp-cli.org/#installing).

## Platform notes

### macOS

Install [Homebrew](https://brew.sh), then `brew install rsync`. Local database tools come with your MySQL/MariaDB or with tools such as MAMP or Local; make sure their `bin` directory is in your `PATH` (see [Troubleshooting]({{ site.baseurl }}/troubleshooting/#mysqldump-command-not-found-locally)). `sshpass` is only needed for password authentication (`brew install hudochenkov/sshpass/sshpass`); prefer keys.

### Linux

Everything comes from your distribution: for Debian and Ubuntu `sudo apt install rsync gzip openssh-client mariadb-client`, then WP-CLI as above.

### Windows

Use WSL (Windows Subsystem for Linux) and run wordmove-ng inside the Linux distribution. Native Windows is not supported.

```powershell
wsl --install
```

Then, inside the Ubuntu shell:

```bash
sudo apt update
sudo apt install -y ruby-full build-essential rsync gzip openssh-client mariadb-client
sudo gem install wordmove-ng
ssh-keygen -t ed25519
```

Add `~/.ssh/id_ed25519.pub` to your host. In `movefile.yml` use Linux paths (`C:\` becomes `/mnt/c/`) and `127.0.0.1` rather than `localhost` for a MySQL server running on Windows. Files under `/mnt/c` all appear with permissions `777`; to get sane permissions on the server add

```yaml
ssh:
  rsync_options: "--chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r"
```
