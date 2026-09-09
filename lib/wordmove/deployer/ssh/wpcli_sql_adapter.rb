module Wordmove
  module Deployer
    module Ssh
      # Database sync using WP-CLI for URL and path adaptation.
      #
      # Both directions follow the same shape: dump the source, import the dump
      # on the target, then run `wp search-replace` on the target. The source
      # database is only ever read, and WP-CLI is required on whichever side is
      # the target of the operation (remote for push, local for pull).
      class WpcliSqlAdapter < SSH
        def check_push_db_prerequisites!
          remote_wp_in_path!
        end

        def check_pull_db_prerequisites!
          return true if wp_in_path?

          raise UnmetPeerDependencyError,
                "WP-CLI is not installed locally or not in your $PATH. It is required "\
                "to adapt the database after import."
        end

        def backup_remote_db!
          download_remote_db(local_gzipped_backup_path)
        end

        def adapt_local_db!
          save_local_db(local_dump_path)
          normalize_collations!(local_dump_path)
          run compress_command(local_dump_path)
          import_remote_dump(local_gzipped_dump_path)
          adapt_remote_db_after_import!
        end

        def after_push_cleanup!
          local_delete(local_gzipped_dump_path)
        end

        def backup_local_db!
          save_local_db(local_backup_path)
          run compress_command(local_backup_path)
        end

        def adapt_remote_db!
          download_remote_db(local_gzipped_dump_path)
          run uncompress_command(local_gzipped_dump_path)
          normalize_collations!(local_dump_path)
          run mysql_import_command(local_dump_path, local_options[:database])
          run_wpcli_search_replace(remote_options, local_options, :vhost)
          run_wpcli_search_replace(remote_options, local_options, :wordpress_path)
        end

        def after_pull_cleanup!
          local_delete(local_dump_path)
        end

        private

        def adapt_remote_db_after_import!
          remote_run_wpcli_search_replace(local_options, remote_options, :vhost)
          remote_run_wpcli_search_replace(local_options, remote_options, :wordpress_path)
        rescue ShellCommandError => e
          logger.error "The remote database was imported but could not be adapted: #{e.message}"
          logger.error "The remote site may now reference the local vhost or path. " \
                       "A backup of the remote database taken before the import is at: " \
                       "#{local_gzipped_backup_path}"
          raise
        end

        def wp_in_path?
          system('which wp > /dev/null 2>&1')
        end

        def wpcli_search_replace(from, to, config_key, path:, remote:)
          return if options[:no_adapt]

          logger.task_step !remote, "adapt dump for #{config_key}"
          return if simulate?

          SqlAdapter::Wpcli.new(from, to, config_key, path, remote: remote).command
        end

        def run_wpcli_search_replace(from, to, config_key)
          command = wpcli_search_replace(
            from, to, config_key, path: local_options[:wordpress_path], remote: false
          )
          run(command) if command
        end

        def remote_run_wpcli_search_replace(from, to, config_key)
          command = wpcli_search_replace(
            from, to, config_key, path: remote_options[:wordpress_path], remote: true
          )
          remote_run(command) if command
        end
      end
    end
  end
end
