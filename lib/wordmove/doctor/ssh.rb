module Wordmove
  class Doctor
    class Ssh
      attr_reader :logger, :movefile

      def initialize(movefile_name = nil, movefile_dir = '.')
        @logger = Logger.new(STDOUT).tap { |l| l.level = Logger::INFO }
        @movefile = Wordmove::Movefile.new(movefile_name, movefile_dir)
      end

      def check!
        logger.task "Checking SSH client"

        if system('which ssh', out: File::NULL, err: File::NULL)
          logger.success "SSH command found"
        else
          logger.error "SSH command not found. And belive me: it's really strange it's not there."
          return
        end

        ssh_environments.each { |name, ssh_options| check_environment!(name, ssh_options) }
      end

      private

      # Returns { environment_name => ssh_options } for every remote using SSH.
      # Any movefile problem is reported by the Movefile doctor, so it is
      # silently skipped here.
      def ssh_environments
        options = movefile.fetch(false)
        options.each_with_object({}) do |(name, env), memo|
          next if %i[local global].include?(name)
          next unless env.is_a?(Hash) && env[:ssh].is_a?(Hash)

          memo[name] = env[:ssh]
        end
      rescue MovefileNotFound, Psych::SyntaxError
        {}
      end

      def check_environment!(name, ssh_options)
        logger.task "Checking SSH connection to \"#{name}\""
        warn_about_gateway_password(name, ssh_options)
        runner = Wordmove::SshRunner.new(ssh_options)
        _stdout, stderr, exit_code = runner.run('true')

        if exit_code.zero?
          logger.success "Non interactive SSH authentication to \"#{name}\" works"
          check_remote_prerequisites!(name, runner)
        else
          logger.error <<-LONG
  Non interactive SSH authentication to "#{name}" failed (exit code #{exit_code}).
                Database sync and remote hooks use `ssh` exactly like rsync does, so
                check your keys, ssh-agent, ~/.ssh/config or the `ssh.password` option.
                The command used to test was:
                #{runner.ssh_argv.join(' ')} true
                #{stderr}
          LONG
        end
      rescue UnmetPeerDependencyError => e
        logger.error e.message
      end

      def check_remote_prerequisites!(name, runner)
        missing = Wordmove::Prerequisites.missing_remotely(runner, Wordmove::Prerequisites::REMOTE_ALL)
        if missing.empty?
          logger.success "All required programs are available on \"#{name}\""
        else
          logger.error <<-LONG
  Missing on "#{name}": #{Wordmove::Prerequisites.describe(missing)}.
                rsync is needed for file sync; gzip, mysql/mariadb, mysqldump/mariadb-dump
                and wp for database sync (wp runs search-replace on the remote after a push).
                Programs must be in the PATH of a non interactive login shell.
          LONG
        end
      rescue ShellCommandError => e
        logger.error e.message
      end

      def warn_about_gateway_password(name, ssh_options)
        gateway = ssh_options[:gateway]
        return unless gateway.is_a?(Hash) && gateway[:password].present?

        logger.warn "\"#{name}\" sets ssh.gateway.password, which cannot be used: the gateway " \
                    "is reached with `ssh -J`, so it must accept your key or ssh-agent. " \
                    "The password is ignored."
      end
    end
  end
end
