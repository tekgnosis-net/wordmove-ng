require 'open3'
require 'shellwords'
require 'time'

module Wordmove
  # Decides, per component, whether local or the remote holds the newer
  # content, so `wordmove-ng auto` can push some components and pull others.
  #
  # Directories are compared by the newest file modification time beneath
  # them; the database by the latest post or comment change on each side.
  # Differences inside `global.auto_window` seconds are treated as in sync.
  # The WordPress core is never decided automatically: its files change on
  # every checkout and on every update, and mirroring it the wrong way is the
  # most destructive mistake possible.
  class AutoPlanner
    class ClockSkewError < StandardError; end

    Row = Struct.new(:task, :local_at, :remote_at, :direction, :reason) do
      def pending?
        %i[push pull].include?(direction)
      end
    end

    DEFAULT_WINDOW = 300
    DEFAULT_CLOCK_SKEW_MAX = 60
    DIRECTORY_TASKS = %w[uploads themes plugins mu_plugins languages].freeze

    attr_reader :warnings, :environment

    def initialize(cli_options)
      @cli_options = cli_options
      @movefile = Wordmove::Movefile.new(cli_options[:config])
      @movefile.load_dotenv(cli_options)
      @options = @movefile.fetch(false)
      @environment = @movefile.environment(cli_options)
      @runner = SshRunner.new(@options[environment][:ssh])
      @warnings = []
    end

    def self.pending?(rows)
      rows.any?(&:pending?)
    end

    # Returns one Row per task, in the given order.
    def plan(tasks)
      check_clock_skew!
      tasks.map { |task| plan_task(task) }
    end

    def window
      knob('WORDMOVE_AUTO_WINDOW', :auto_window, DEFAULT_WINDOW)
    end

    def clock_skew_max
      knob('WORDMOVE_AUTO_CLOCK_SKEW_MAX', :auto_clock_skew_max, DEFAULT_CLOCK_SKEW_MAX)
    end

    private

    def plan_task(task)
      return Row.new(task, nil, nil, :skip, 'core is never decided automatically') if core?(task)

      local_at, local_err = probe(:local, task)
      remote_at, remote_err = probe(:remote, task)
      error = probe_error(local_err, remote_err)
      return Row.new(task, local_at, remote_at, :error, error) if error

      direction, reason = decide(local_at, remote_at)
      direction, reason = apply_forbid(task, direction, reason)
      Row.new(task, local_at, remote_at, direction, reason)
    end

    def core?(task)
      task == 'wordpress'
    end

    def probe_error(local_err, remote_err)
      return "local probe failed: #{local_err}" if local_err
      return "remote probe failed: #{remote_err}" if remote_err

      nil
    end

    def decide(local_at, remote_at)
      return [:skip, 'both sides empty'] if local_at.nil? && remote_at.nil?
      return [:push, 'remote empty'] if remote_at.nil?
      return [:pull, 'local empty'] if local_at.nil?

      delta = (remote_at - local_at).to_i
      return [:skip, "in sync (within #{window}s)"] if delta.abs <= window

      delta.positive? ? [:pull, "remote newer by #{delta}s"] : [:push, "local newer by #{-delta}s"]
    end

    def apply_forbid(task, direction, reason)
      return [direction, reason] unless %i[push pull].include?(direction)

      forbidden = @options.dig(environment, :forbid, direction, task.to_sym) == true
      return [direction, reason] unless forbidden

      [:blocked, "#{reason}; #{direction} forbidden by movefile"]
    end

    # Returns [epoch_or_nil, error_or_nil]. Probe output comes from a remote
    # host and is treated as untrusted: anything that is not a plain number or
    # timestamp is reported as an error rather than interpreted.
    def probe(side, task)
      command = task == 'db' ? db_command(side) : dir_command(side, task)
      stdout, stderr, code = execute(side, command)
      return [nil, stderr.to_s.strip.empty? ? "exit #{code}" : stderr.strip] unless code.zero?

      [task == 'db' ? parse_db(stdout) : parse_epoch(stdout), nil]
    rescue ArgumentError => e
      [nil, "unparseable output: #{e.message}"]
    end

    def dir_command(side, task)
      path = WordpressDirectory.new(task.to_sym, side_options(side)).path
      # Newest regular file mtime under the directory; empty output if none.
      "find #{Shellwords.escape(path)} -type f -printf '%T@\\n' 2>/dev/null | sort -n | tail -1"
    end

    # Latest post and comment change, one per line. The table prefix is read
    # with `wp db prefix` so custom prefixes work; wp handles the credentials.
    def db_command(side)
      path = Shellwords.escape(side_options(side)[:wordpress_path])
      prefix = "$(wp db prefix --path=#{path} --allow-root)"
      sql = "SELECT MAX(post_modified_gmt) FROM #{prefix}posts " \
            "UNION ALL SELECT MAX(comment_date_gmt) FROM #{prefix}comments"
      "wp db query \"#{sql}\" --skip-column-names --path=#{path} --allow-root"
    end

    EPOCH = /\A\d+(\.\d+)?\z/
    TIMESTAMP = /\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\z/

    def parse_epoch(stdout)
      value = stdout.to_s.strip
      return nil if value.empty?
      raise ArgumentError, "expected an epoch, got #{value.inspect[0, 40]}" unless value.match?(EPOCH)

      value.to_f
    end

    def parse_db(stdout)
      stamps = stdout.to_s.lines.map(&:strip).reject { |l| l.empty? || l == 'NULL' }
      return nil if stamps.empty?

      stamps.map do |stamp|
        raise ArgumentError, "expected a timestamp, got #{stamp.inspect[0, 40]}" unless stamp.match?(TIMESTAMP)

        Time.parse("#{stamp} UTC").to_i
      end.max
    end

    def check_clock_skew!
      local_out, local_err, local_code = local_shell('date +%s')
      rout, rerr, rcode = @runner.run('date +%s')
      raise ClockSkewError, "could not read the local clock: #{local_err}" unless local_code.zero?
      raise ClockSkewError, "could not read the remote clock: #{rerr}" unless rcode.zero?

      skew = (rout.to_i - local_out.to_i).abs
      if skew > clock_skew_max
        raise ClockSkewError,
              "clock skew of #{skew}s between local and \"#{environment}\" exceeds the " \
              "maximum of #{clock_skew_max}s; fix the clocks (ntp) before trusting timestamps"
      end
      @warnings << "clock skew of #{skew}s between local and \"#{environment}\"" if skew.positive?
    end

    def execute(side, command)
      side == :local ? local_shell(command) : @runner.run(command)
    end

    def local_shell(command)
      stdout, stderr, status = Open3.capture3('sh', '-c', command)
      [stdout, stderr, status.exitstatus]
    end

    def side_options(side)
      side == :local ? @options[:local] : @options[environment]
    end

    def knob(env_name, key, default)
      raw = ENV.fetch(env_name, nil)
      raw = @options.dig(:global, key) if raw.nil? || raw.to_s.strip.empty?
      value = raw.nil? ? default : raw.to_i
      value.clamp(0, 86_400 * 30)
    end
  end
end
