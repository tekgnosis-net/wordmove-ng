module Wordmove
  class Doctor
    class Movefile
      MANDATORY_SECTIONS = %i[local].freeze
      OPTIONAL_SECTIONS = %i[global].freeze
      attr_reader :movefile, :contents, :root_keys

      def initialize(name = nil, dir = '.')
        @movefile = Wordmove::Movefile.new(name, dir)

        begin
          @contents = movefile.fetch
          @root_keys = contents.keys
        rescue Psych::SyntaxError
          movefile.logger.error "Your movefile is not parsable due to a syntax error"\
                                "so we can't continue to validate it."
          movefile.logger.debug "You could try to use https://yamlvalidator.com/ to"\
                                "get a clue about the problem."
        end
      end

      def validate!
        return false unless root_keys

        MANDATORY_SECTIONS.each do |key|
          movefile.logger.task "Validating movefile section: #{key}"
          validate_mandatory_section(key)
        end

        OPTIONAL_SECTIONS.each do |key|
          next unless root_keys.delete(key)

          movefile.logger.task "Validating movefile section: #{key}"
          validate_section(key)
        end

        root_keys.each do |remote|
          movefile.logger.task "Validating movefile section: #{remote}"
          validate_remote_section(remote)
        end
      end

      private

      def validate_section(key)
        validator = validator_for(key)

        errors = validator.validate(contents[key].deep_stringify_keys)

        if errors&.empty?
          movefile.logger.success "Formal validation passed"

          return true
        end

        errors.each do |e|
          movefile.logger.error "[#{e.path}] #{e.message}"
        end
      end

      def validate_mandatory_section(key)
        return false unless root_keys.delete(key) do
          movefile.logger.error "#{key} section not present"

          false
        end

        validate_section(key)
      end

      def validate_remote_section(key)
        return false unless validate_protocol_presence(contents[key].keys)

        validate_prefix_collisions(key)
        validate_section(key)
      end

      def validate_prefix_collisions(key)
        movefile.prefix_collisions(key).each do |short, long|
          movefile.logger.error "\"#{short}\" is a prefix of \"#{long}\": wp search-replace "\
                                "would rewrite the longer value too. Use distinct vhosts "\
                                "and wordpress_paths for local and #{key}."
        end
      end

      def validate_protocol_presence(keys)
        if keys.include?(:ftp)
          movefile.logger.error "This remote is configured with `ftp`, but FTP support was "\
                                "removed in wordmove-ng 6.0. Switch it to `ssh`."
          return false
        end
        return true if keys.include?(:ssh)

        movefile.logger.error "This remote has no ssh protocol defined"

        false
      end

      def validator_for(key)
        suffix = if (MANDATORY_SECTIONS + OPTIONAL_SECTIONS).include? key
                   key
                 else
                   'remote'
                 end

        schema = Kwalify::Yaml.load_file("#{__dir__}/../assets/wordmove_schema_#{suffix}.yml")

        Kwalify::Validator.new(schema)
      end
    end
  end
end
