module Wordmove
  # Helpers behind `wordmove-ng auto`, kept out of the Thor class so the
  # command definitions stay readable.
  module AutoCommand
    private

    def selected_tasks(options)
      tasks = []
      handle_options(options) { |task| tasks << task }
      tasks
    end

    def print_auto_plan(rows, warnings, environment)
      logger.task "Auto plan for \"#{environment}\""
      warnings.each { |w| logger.warn(w) }
      width = rows.map { |r| r.task.length }.max
      rows.each do |row|
        logger.plain format(
          "  %-#{width}s  %-7s  local %-20s  remote %-20s  %s",
          row.task, row.direction.to_s.upcase, stamp(row.local_at), stamp(row.remote_at),
          row.reason
        )
      end
    end

    def stamp(epoch)
      epoch.nil? ? '-' : Time.at(epoch).strftime('%Y-%m-%d %H:%M:%S')
    end

    def apply_auto_plan(rows, options)
      deployer = Wordmove::Deployer::Base.deployer_for(options.deep_symbolize_keys)
      %i[push pull].each do |action|
        tasks = rows.select { |r| r.direction == action }.map(&:task)
        next if tasks.empty?

        Wordmove::Hook.run(action, :before, options)
        guardian = Wordmove::Guardian.new(options: options, action: action)
        tasks.each { |task| deployer.send("#{action}_#{task}") if guardian.allows(task.to_sym) }
        Wordmove::Hook.run(action, :after, options)
      end
    end
  end
end
