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
        runner = Wordmove::SshRunner.new(ssh_options)
        _stdout, stderr, exit_code = runner.run('true')

        if exit_code.zero?
          logger.success "Non interactive SSH authentication to \"#{name}\" works"
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
    end
  end
end
