require 'pathname'

module Wordmove
  module Deployer
    class SSH < Base
      attr_reader :local_dump_path,
                  :local_backup_path,
                  :local_gzipped_dump_path,
                  :local_gzipped_backup_path

      def initialize(environment, options)
        super(environment, options)

        ssh_options = remote_options[:ssh]

        # The runner must be built before Photocopier, which strips :gateway and
        # :rsync_options out of the very same hash.
        @runner = SshRunner.new(ssh_options)

        if simulate? && ssh_options[:rsync_options]
          ssh_options[:rsync_options].concat(" --dry-run")
        elsif simulate?
          ssh_options[:rsync_options] = "--dry-run"
        end

        @copier = Photocopier::SSH.new(ssh_options).tap { |c| c.logger = logger }

        @local_dump_path = local_wp_content_dir.path("dump.sql")
        @local_backup_path = local_wp_content_dir.path("local-backup-#{Time.now.to_i}.sql")
        @local_gzipped_dump_path = local_dump_path + '.gz'
        @local_gzipped_backup_path = local_wp_content_dir
                                     .path("#{environment}-backup-#{Time.now.to_i}.sql.gz")
      end

      private

      def push_db
        super

        return true if simulate?

        check_push_db_prerequisites!
        backup_remote_db!
        adapt_local_db!
        after_push_cleanup!
      end

      def pull_db
        super

        return true if simulate?

        check_pull_db_prerequisites!
        backup_local_db!
        adapt_remote_db!
        after_pull_cleanup!
      end

      # Hooks for adapters that need peer dependencies (e.g. wp-cli) on one side.
      # They run before any backup or dump so a missing dependency has no side effects.
      def check_push_db_prerequisites!; end

      def check_pull_db_prerequisites!; end

      # Directory transfers go through rsync (Photocopier), which honours the
      # --dry-run option set in #initialize when simulating.
      %w[get_directory put_directory].each do |command|
        define_method "remote_#{command}" do |*args|
          logger.task_step false, "#{command}: #{args.join(' ')}"
          @copier.send(command, *args)
        end
      end

      # Single file transfers and deletes go through the system scp/ssh binaries.
      def remote_get(remote_path, local_path)
        logger.task_step false, "get: #{remote_path} #{local_path}"
        return true if simulate?

        ensure_success!(@runner.get(remote_path, local_path), "get #{remote_path}")
      end

      def remote_put(local_path, remote_path)
        logger.task_step false, "put: #{local_path} #{remote_path}"
        return true if simulate?

        ensure_success!(@runner.put(local_path, remote_path), "put #{remote_path}")
      end

      def remote_delete(remote_path)
        logger.task_step false, "delete: #{remote_path}"
        return true if simulate?

        ensure_success!(@runner.delete(remote_path), "delete #{remote_path}")
      end

      def remote_run(command)
        logger.task_step false, command
        return true if simulate?

        ensure_success!(@runner.run(command), command)
      end

      def ensure_success!(result, description)
        _stdout, stderr, exit_code = result
        return true if exit_code.zero?

        raise(
          ShellCommandError,
          "Error code #{exit_code} returned by command \"#{description}\": #{stderr}"
        )
      end

      def remote_wp_in_path!
        _stdout, _stderr, exit_code = @runner.run('command -v wp')
        return true if exit_code.zero?

        raise UnmetPeerDependencyError,
              "WP-CLI is not installed on the \"#{environment}\" host (or not in the "\
              "login shell $PATH). It is required there to adapt the database after import."
      end

      def download_remote_db(local_gizipped_dump_path)
        remote_dump_path = remote_wp_content_dir.path("dump.sql")
        # dump remote db into file
        remote_run mysql_dump_command(remote_options[:database], remote_dump_path)
        remote_run compress_command(remote_dump_path)
        remote_dump_path += '.gz'
        # download remote dump
        remote_get(remote_dump_path, local_gizipped_dump_path)
        remote_delete(remote_dump_path)
      end

      def import_remote_dump(local_gizipped_dump_path)
        remote_dump_path = remote_wp_content_dir.path("dump.sql")
        remote_gizipped_dump_path = remote_dump_path + '.gz'

        remote_put(local_gizipped_dump_path, remote_gizipped_dump_path)
        remote_run uncompress_command(remote_gizipped_dump_path)
        remote_run mysql_import_command(remote_dump_path, remote_options[:database])
        remote_delete(remote_dump_path)
      end

      %w[uploads themes plugins mu_plugins languages].each do |task|
        define_method "push_#{task}" do
          logger.task "Pushing #{task.titleize}"
          local_path = local_options[:wordpress_path]
          remote_path = remote_options[:wordpress_path]

          remote_put_directory(local_path, remote_path,
                               push_exclude_paths(task), push_inlcude_paths(task))
        end

        define_method "pull_#{task}" do
          logger.task "Pulling #{task.titleize}"
          local_path = local_options[:wordpress_path]
          remote_path = remote_options[:wordpress_path]

          remote_get_directory(remote_path, local_path,
                               pull_exclude_paths(task), pull_include_paths(task))
        end
      end

      def push_inlcude_paths(task)
        Pathname.new(send(:"local_#{task}_dir").relative_path)
                .ascend
                .each_with_object([]) do |directory, array|
                  path = directory.to_path
                  path.prepend('/') unless path.match? %r{^/}
                  path.concat('/') unless path.match? %r{/$}
                  array << path
                end
      end

      def push_exclude_paths(task)
        Pathname.new(send(:"local_#{task}_dir").relative_path)
                .dirname
                .ascend
                .each_with_object([]) do |directory, array|
                  path = directory.to_path
                  path.prepend('/') unless path.match? %r{^/}
                  path.concat('/') unless path.match? %r{/$}
                  path.concat('*')
                  array << path
                end
                .concat(paths_to_exclude)
                .concat(['/*'])
      end

      def pull_include_paths(task)
        Pathname.new(send(:"remote_#{task}_dir").relative_path)
                .ascend
                .each_with_object([]) do |directory, array|
                  path = directory.to_path
                  path.prepend('/') unless path.match? %r{^/}
                  path.concat('/') unless path.match? %r{/$}
                  array << path
                end
      end

      def pull_exclude_paths(task)
        Pathname.new(send(:"remote_#{task}_dir").relative_path)
                .dirname
                .ascend
                .each_with_object([]) do |directory, array|
                  path = directory.to_path
                  path.prepend('/') unless path.match? %r{^/}
                  path.concat('/') unless path.match? %r{/$}
                  path.concat('*')
                  array << path
                end
                .concat(paths_to_exclude)
                .concat(['/*'])
      end
    end
  end
end
