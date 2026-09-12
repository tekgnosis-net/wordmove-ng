---
title: Contributing and releasing
nav_order: 12
---

# Contributing and releasing
{: .no_toc }

1. TOC
{:toc}

## Reporting a bug

Run `wordmove-ng doctor` first and include its output. Then open an issue with the command you ran, the relevant part of `movefile.yml` with secrets removed, the full error output, and your OS, Ruby (`ruby --version`) and wordmove-ng (`wordmove-ng --version`) versions. Only the latest release is supported; bugs in the legacy `wordmove` 5.x gem belong to its own tracker.

## Development

```bash
git clone https://github.com/tekgnosis-net/wordmove-ng.git
cd wordmove-ng
bundle install
bundle exec rake                                 # specs + rubocop, what CI runs
bundle exec rspec spec/deployer/ssh_db_spec.rb   # one file
bin/wordmove-ng --help                           # run from the checkout, from any directory
```

CI runs the suite and rubocop on Ruby 3.0 through 4.0. Code must run on all of them. New rubocop offences are fixed rather than added to `.rubocop_todo.yml`, which only grandfathers the pre-6.0 backlog.

Repository layout, request flow and conventions are described in [`CLAUDE.md`](https://github.com/tekgnosis-net/wordmove-ng/blob/master/CLAUDE.md).

## Commit messages

Write [Conventional Commits](https://www.conventionalcommits.org): `fix: …` (patch), `feat: …` (minor), `feat!: …` or a `BREAKING CHANGE:` footer (major), and `docs:`, `chore:`, `ci:`, `test:`, `refactor:` for everything that does not ship a change. The version number and `CHANGELOG.md` are generated from them; never edit `lib/wordmove/version.rb` or the changelog by hand.

## Releasing

Releases are automated by [release-please](https://github.com/googleapis/release-please) and published to [rubygems.org](https://rubygems.org/gems/wordmove-ng) with [trusted publishing](https://guides.rubygems.org/trusted-publishing/), so no API key is stored anywhere.

1. Every push to `master` updates a "release PR" that bumps the version and the changelog from the commits since the last release. release-please proposes a patch release for any Conventional Commit, `ci:` and `docs:` included, so merge the PR only when there is something worth shipping.
2. Merging it creates the `vX.Y.Z` tag and the GitHub release.
3. The `publish` job in `.github/workflows/release.yml` re-runs the suite on the tagged commit, builds the gem, pushes it to rubygems.org and attaches the `.gem` file to the GitHub release.

Pushing a `v*` tag by hand at the head of `master` triggers the same publish job.

`master` is protected: changes land through pull requests whose `test` checks pass, and the rules apply to administrators too. release-please opens its PR with a fine-grained personal access token (secret `RELEASE_PLEASE_TOKEN`) because PRs opened with the built-in Actions token never trigger the checks.

## This documentation

The site is built from the `docs/` folder on `master` with Jekyll and the just-the-docs theme by `.github/workflows/pages.yml`. Preview locally with

```bash
cd docs && bundle install && bundle exec jekyll serve
```

Please keep it, and the README, updated when changing user-facing behaviour.
