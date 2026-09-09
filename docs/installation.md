---
title: Installation
nav_order: 2
---

# Installation
{: .no_toc }

1. TOC
{:toc}

## Ruby

wordmove-ng needs **Ruby 3.0 or newer**. Check with `ruby --version`. If your system Ruby is older or missing, use a version manager:

- [rbenv](https://github.com/rbenv/rbenv#installation)
- [RVM](https://rvm.io/)
- [mise](https://mise.jdx.dev/) (`mise use -g ruby@3.4`)

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
