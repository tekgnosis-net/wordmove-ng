require 'open3'
require 'shellwords'

module Wordmove
  # Checks that the external binaries a database sync relies on exist, either
  # on this machine or on a remote host reached through an SshRunner.
  #
  # A requirement is a binary name, or an array of alternatives of which at
  # least one must exist (e.g. mysql or mariadb).
  module Prerequisites
    # Needed where the dump is produced.
    DB_SOURCE = ['gzip', %w[mysqldump mariadb-dump]].freeze
    # Needed where the dump is imported and adapted.
    DB_TARGET = ['gzip', %w[mysql mariadb], 'wp'].freeze
    # Everything a remote may be asked for, used by the doctor.
    REMOTE_ALL = ['rsync', 'gzip', %w[mysql mariadb], %w[mysqldump mariadb-dump], 'wp'].freeze

    class << self
      # POSIX sh snippet printing, one per line, the requirements that are not
      # satisfied. Alternatives are printed joined with "|".
      def probe_command(requirements)
        requirements.map do |requirement|
          names = Array(requirement)
          test = names.map { |n| "command -v #{Shellwords.escape(n)} >/dev/null 2>&1" }.join(' || ')
          "#{test} || echo #{Shellwords.escape(names.join('|'))}"
        end.join('; ')
      end

      def missing_locally(requirements)
        stdout, _stderr, _status = Open3.capture3('sh', '-c', probe_command(requirements))
        parse(stdout)
      end

      # Returns the missing requirements, or raises ShellCommandError when the
      # probe itself could not run (e.g. authentication failed).
      def missing_remotely(runner, requirements)
        stdout, stderr, exit_code = runner.run(probe_command(requirements))
        unless exit_code.zero?
          raise ShellCommandError,
                "Could not check the remote prerequisites (exit code #{exit_code}): #{stderr}"
        end

        parse(stdout)
      end

      def describe(missing)
        missing.map { |names| names.join(' or ') }.join(', ')
      end

      private

      def parse(stdout)
        stdout.lines.map(&:strip).reject(&:empty?).map { |line| line.split('|') }
      end
    end
  end
end
