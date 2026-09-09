require 'shellwords'

module Wordmove
  module SqlAdapter
    class Wpcli
      attr_accessor :sql_content
      attr_reader :from, :to, :local_path, :remote

      # When +remote+ is true the command is meant to be executed on the remote
      # host: +local_path+ is then the remote wordpress_path and is used as-is,
      # and no local wp-cli availability or configuration probing is done.
      def initialize(source_config, dest_config, config_key, local_path, remote: false)
        @from = source_config[config_key]
        @to = dest_config[config_key]
        @local_path = local_path
        @remote = remote
      end

      def command
        unless remote || wp_in_path?
          raise UnmetPeerDependencyError, "WP-CLI is not installed or not in your $PATH"
        end

        opts = [
          "--path=#{Shellwords.escape(cli_config_path)}",
          Shellwords.escape(from.to_s),
          Shellwords.escape(to.to_s),
          "--quiet",
          "--skip-columns=guid",
          "--all-tables",
          "--allow-root"
        ]

        "wp search-replace #{opts.join(' ')}"
      end

      private

      def wp_in_path?
        system('which wp > /dev/null 2>&1')
      end

      def cli_config_path
        return local_path if remote

        load_from_yml || load_from_cli || local_path
      end

      def load_from_yml
        cli_config_path = File.join(local_path, "wp-cli.yml")
        return unless File.exist?(cli_config_path)

        YAML.load_file(cli_config_path).with_indifferent_access["path"]
      end

      def load_from_cli
        raw = `wp cli param-dump --allow-root --with-values`
        cli_config = JSON.parse(raw, symbolize_names: true)
        cli_config.dig(:path, :current)
      end
    end
  end
end
