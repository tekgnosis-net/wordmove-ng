module Wordmove
  class CLI < Thor
    include AutoCommand

    map %w[--version -v] => :__print_version

    desc "--version, -v", "Print the version"
    def __print_version
      puts Wordmove::VERSION
    end

    desc "init", "Generates a brand new movefile.yml"
    def init
      Wordmove::Generators::Movefile.start
    end

    desc "doctor", "Do some local configuration and environment checks"
    def doctor
      Wordmove::Doctor.start
    rescue Wordmove::MovefileNotFound => e
      logger.error(e.message)
      exit 1
    rescue Psych::SyntaxError => e
      logger.error("Your movefile is not parsable due to a syntax error: #{e.message}")
      exit 1
    end

    shared_options = {
      wordpress: { aliases: "-w", type: :boolean },
      uploads: { aliases: "-u", type: :boolean },
      themes: { aliases: "-t", type: :boolean },
      plugins: { aliases: "-p", type: :boolean },
      mu_plugins: { aliases: "-m", type: :boolean },
      languages: { aliases: "-l", type: :boolean },
      db: { aliases: "-d", type: :boolean },
      verbose: { aliases: "-v", type: :boolean },
      simulate: { aliases: "-s", type: :boolean },
      environment: { aliases: "-e" },
      config: { aliases: "-c" },
      debug: { type: :boolean },
      no_adapt: { type: :boolean },
      all: { type: :boolean }
    }

    no_tasks do
      def handle_options(options)
        wordpress_options.each do |task|
          yield task if options[task] || (options["all"] && options[task] != false)
        end
      end

      def wordpress_options
        %w[wordpress uploads themes plugins mu_plugins languages db]
      end

      def ensure_wordpress_options_presence!(options)
        return if (options.keys & (wordpress_options + ["all"])).present?

        puts "No options given. See wordmove --help"
        exit 1
      end

      def logger
        Logger.new(STDOUT).tap { |l| l.level = Logger::DEBUG }
      end
    end

    desc "list", "List all environments and vhosts"
    shared_options.each do |option, args|
      method_option option, args
    end
    def list
      Wordmove::EnvironmentsList.print(options)
    rescue Wordmove::MovefileNotFound => e
      logger.error(e.message)
      exit 1
    rescue Psych::SyntaxError => e
      logger.error("Your movefile is not parsable due to a syntax error: #{e.message}")
      exit 1
    end

    desc "pull", "Pulls WP data from remote host to the local machine"
    shared_options.each do |option, args|
      method_option option, args
    end
    def pull
      ensure_wordpress_options_presence!(options)
      begin
        deployer = Wordmove::Deployer::Base.deployer_for(options.deep_symbolize_keys)
      rescue MovefileNotFound => e
        logger.error(e.message)
        exit 1
      rescue Psych::SyntaxError => e
        logger.error("Your movefile is not parsable due to a syntax error: #{e.message}")
        exit 1
      end

      Wordmove::Hook.run(:pull, :before, options)

      guardian = Wordmove::Guardian.new(options: options, action: :pull)

      handle_options(options) do |task|
        deployer.send("pull_#{task}") if guardian.allows(task.to_sym)
      end

      Wordmove::Hook.run(:pull, :after, options)
    end

    desc "auto", "Decides per component whether to push or pull, from timestamps on both sides"
    long_desc <<-LONGDESC
      Compares each selected component on local and on the remote (newest file
      modification time for directories, latest post or comment change for the
      database) and proposes a direction per component. The WordPress core is
      never decided automatically.

      Without --apply only the plan is printed and nothing changes; the exit
      code is 3 when at least one component would move, 0 when everything is in
      sync. With --apply the plan is executed through the regular push and pull
      steps, honouring --simulate, forbid rules and hooks.
    LONGDESC
    shared_options.each do |option, args|
      method_option option, args
    end
    method_option :apply, type: :boolean, default: false,
                          desc: "Execute the plan instead of only printing it"
    # rubocop:disable-next Metrics/MethodLength
    def auto
      ensure_wordpress_options_presence!(options)
      begin
        planner = Wordmove::AutoPlanner.new(options.deep_symbolize_keys)
        rows = planner.plan(selected_tasks(options))
      rescue MovefileNotFound, Wordmove::AutoPlanner::ClockSkewError,
             UndefinedEnvironment, UnmetPeerDependencyError => e
        logger.error(e.message)
        exit 1
      rescue Psych::SyntaxError => e
        logger.error("Your movefile is not parsable due to a syntax error: #{e.message}")
        exit 1
      end

      print_auto_plan(rows, planner.warnings, planner.environment)

      if rows.any? { |r| r.direction == :error }
        logger.error "Some components could not be compared; nothing was changed."
        exit 1
      end

      unless Wordmove::AutoPlanner.pending?(rows)
        logger.success "Nothing to do."
        return
      end

      unless options[:apply]
        logger.info "Plan only. Re-run with --apply to execute it (add -s for a dry run)."
        exit 3
      end

      apply_auto_plan(rows, options)
    end

    desc "push", "Pushes WP data from local machine to remote host"
    shared_options.each do |option, args|
      method_option option, args
    end
    def push
      ensure_wordpress_options_presence!(options)
      begin
        deployer = Wordmove::Deployer::Base.deployer_for(options.deep_symbolize_keys)
      rescue MovefileNotFound => e
        logger.error(e.message)
        exit 1
      rescue Psych::SyntaxError => e
        logger.error("Your movefile is not parsable due to a syntax error: #{e.message}")
        exit 1
      end

      Wordmove::Hook.run(:push, :before, options)

      guardian = Wordmove::Guardian.new(options: options, action: :push)

      handle_options(options) do |task|
        deployer.send("push_#{task}") if guardian.allows(task.to_sym)
      end

      Wordmove::Hook.run(:push, :after, options)
    end
  end
end
