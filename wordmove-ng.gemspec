lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'wordmove/version'

Gem::Specification.new do |spec|
  spec.name          = "wordmove-ng"
  spec.version       = Wordmove::VERSION
  spec.authors       = [
    "Kumar",
    # Original Wordmove authors (weLaika)
    "Stefano Verna", "Ju Liu", "Fabrizio Monti", "Alessandro Fazzi", "Filippo Gangi Dino"
  ]
  spec.email         = ["kumar@tekgnosis.net"]

  spec.summary       = "Sync WordPress files and database between environments over SSH"
  spec.description   = <<~DESC
    Maintained successor of Wordmove. Pushes and pulls WordPress core, uploads, themes,
    plugins, languages and the database between a local install and remote hosts over
    SSH and rsync, adapting URLs and paths with wp-cli on the target.
  DESC
  spec.homepage      = "https://github.com/tekgnosis-net/wordmove-ng"
  spec.license       = "MIT"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "documentation_uri" => "https://tekgnosis-net.github.io/wordmove-ng/",
    "rubygems_mfa_required" => "true"
  }

  spec.files         = `git ls-files -z`
                       .split("\x0")
                       .reject { |f| f.match(%r{^(test|spec|features|supertool)/}) }

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", '~> 6.1'
  spec.add_dependency "base64", "~> 0.1"
  spec.add_dependency "benchmark", ">= 0.4", "< 1"
  spec.add_dependency "bigdecimal", "~> 4.0"
  spec.add_dependency "colorize", "~> 0.8.1"
  spec.add_dependency "dotenv", "~> 2.7.5"
  spec.add_dependency "kwalify", "~> 0"
  spec.add_dependency "logger", ">= 1.6", "< 2"
  spec.add_dependency "mutex_m", "~> 0.1"
  spec.add_dependency "ostruct", "~> 0.6"
  spec.add_dependency "photocopier", "~> 1.4", ">= 1.4.0"
  spec.add_dependency "thor", "~> 1.4"

  spec.required_ruby_version = ">= 3.0.0"

  spec.post_install_message = <<-MSG
    wordmove-ng 6.0 is a breaking release compared to wordmove 5.x:
    the executable is `wordmove-ng`, FTP is gone, Ruby >= 3.0 is required
    and `wp` must be installed on the target of a database sync.
    Upgrade guide: https://github.com/tekgnosis-net/wordmove-ng#upgrading-from-wordmove-5x
  MSG
end
