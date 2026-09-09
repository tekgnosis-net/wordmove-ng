require 'open3'
require 'shellwords'

module Wordmove
  # Runs remote commands and file transfers through the system `ssh` and `scp`
  # binaries, so that authentication behaves exactly like the rsync transfers:
  # ssh-agent, ~/.ssh/config, ProxyJump and modern signature algorithms all work
  # without any Ruby-side SSH implementation.
  #
  # When no password is configured the connection runs in BatchMode, so a failed
  # key authentication is reported as an error instead of an interactive prompt.
  class SshRunner
    attr_reader :options

    def initialize(ssh_options)
      @options = (ssh_options || {}).dup
    end

    # Returns [stdout, stderr, exit_code]
    def run(command)
      execute(ssh_argv + [command])
    end

    def get(remote_path, local_path)
      execute(scp_argv + [remote_file(remote_path), local_path])
    end

    def put(local_path, remote_path)
      execute(scp_argv + [local_path, remote_file(remote_path)])
    end

    def delete(remote_path)
      run("rm -rf #{Shellwords.escape(remote_path)}")
    end

    def ssh_argv
      wrap_password(['ssh'] + common_arguments + port_arguments('-p') + [target])
    end

    def scp_argv
      wrap_password(['scp', '-q'] + common_arguments + port_arguments('-P'))
    end

    def password?
      options[:password].present?
    end

    private

    def execute(argv)
      stdout, stderr, status = Open3.capture3(*argv)
      [stdout, stderr, status.exitstatus]
    rescue Errno::ENOENT
      binary = argv.first
      raise UnmetPeerDependencyError,
            "`#{binary}` is not installed or not in your $PATH; it is required for SSH "\
            "database operations and remote hooks"
    end

    def target
      user = options[:user]
      user.present? ? "#{user}@#{options[:host]}" : options[:host].to_s
    end

    def remote_file(path)
      # scp hands the remote path to the remote shell, so it needs shell escaping.
      "#{target}:#{Shellwords.escape(path)}"
    end

    def common_arguments
      arguments = []
      arguments.concat(%w[-o BatchMode=yes]) unless password?
      arguments.concat(['-J', jump_host]) if gateway?
      arguments
    end

    def port_arguments(flag)
      return [] unless options[:port].present?

      [flag, options[:port].to_s]
    end

    def wrap_password(argv)
      return argv unless password?

      ['sshpass', '-p', options[:password].to_s] + argv
    end

    def gateway?
      options[:gateway].is_a?(Hash) && options[:gateway][:host].present?
    end

    def jump_host
      gateway = options[:gateway]
      spec = gateway[:host].to_s
      spec = "#{gateway[:user]}@#{spec}" if gateway[:user].present?
      spec = "#{spec}:#{gateway[:port]}" if gateway[:port].present?
      spec
    end
  end
end
