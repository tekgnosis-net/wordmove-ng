module Wordmove
  class Doctor
    class Wpcli
      attr_reader :logger, :movefile

      def initialize(movefile_name = nil, movefile_dir = '.')
        @logger = Logger.new(STDOUT).tap { |l| l.level = Logger::INFO }
        @movefile = Wordmove::Movefile.new(movefile_name, movefile_dir)
      end

      def check!
        logger.task "Checking local wp-cli installation"

        if in_path?
          logger.success "wp-cli is correctly installed"

          if up_to_date?
            logger.success "wp-cli is up to date"
          else
            logger.error <<-LONG
  wp-cli is not up to date.
                Use `wp cli update` to update to the latest version.
            LONG
          end
        else
          logger.error <<-LONG
  wp-cli is not installed (or not in your $PATH).
              Read http://wp-cli.org/#installing for installation info.
          LONG
        end

        ssh_environments.each { |name, ssh_options| check_remote!(name, ssh_options) }
      end

      private

      def in_path?
        system('which wp', out: File::NULL)
      end

      def up_to_date?
        `wp cli check-update --format=json --allow-root`.empty?
      end

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

      def check_remote!(name, ssh_options)
        logger.task "Checking wp-cli installation on \"#{name}\""
        _stdout, _stderr, exit_code = Wordmove::SshRunner.new(ssh_options).run('command -v wp')

        if exit_code.zero?
          logger.success "wp-cli is available on \"#{name}\""
        else
          logger.error <<-LONG
  wp-cli is not available on "#{name}" (or not in the login shell $PATH).
                With the `wpcli` SQL adapter, `wordmove push -d` imports the dump on the
                remote and then runs `wp search-replace` there, so wp-cli is required
                on the remote host.
          LONG
        end
      rescue UnmetPeerDependencyError => e
        logger.error e.message
      end
    end
  end
end
