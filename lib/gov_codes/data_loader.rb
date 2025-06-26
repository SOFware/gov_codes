require "yaml"

module GovCodes
  # DataLoader module provides shared functionality for loading YAML data
  # from multiple paths in the lookup array
  module DataLoader
    def self.extended(base)
      base.const_set(:CODES, {})
      base.private_constant(:CODES)
    end

    def data(lookup: $LOAD_PATH)
      data = {}

      # Handle nil or empty lookup
      return data if lookup.nil? || lookup.empty?

      # Add the gem's lib directory to the lookup path
      gem_lib_dir = File.expand_path("../../", __FILE__)
      lookup = [gem_lib_dir] + Array(lookup)

      namespace_parts = name.split("::")
        .map { it.gsub(/([A-Z])([a-z])/, '_\1\2').downcase }
        .map { it.sub(/^_/, "") }

      # Append .yml to the last item
      namespace_parts[-1] = "#{namespace_parts[-1]}.yml"

      # Iterate through each path in the lookup array
      files = lookup.map do |dir|
        yaml_path = File.join(dir, *namespace_parts)
        yaml_path if File.exist?(yaml_path)
      end
        .compact
        .uniq

      files.each do |path|
        yaml_data = YAML.load_file(path, symbolize_names: true)
        # Handle nil or empty YAML data
        if yaml_data&.is_a?(Hash)
          data.merge!(yaml_data)
        end
      rescue Psych::SyntaxError, TypeError
        # Handle invalid YAML gracefully
        next
      end

      data
    end

    def reset_data(lookup: $LOAD_PATH)
      remove_const(:DATA)
      const_set(:DATA, data(lookup:).freeze)
      remove_const(:CODES)
      const_set(:CODES, {})
    end

    def find_name_recursive(result)
      # Start with the career field (e.g., "1N")
      base_code = result[:career_field].to_sym

      loaded_data = self::DATA
      # Look up in the codes hash
      if loaded_data[base_code]
        # If we have a subcategory, try to find a more specific name
        if result[:subcategory] &&
            loaded_data.dig(base_code, :subcategories) &&
            loaded_data.dig(base_code, :subcategories, result[:subcategory])

          subdivision = loaded_data.dig(base_code, :subcategories, result[:subcategory])
          # If we have a shredout, try to find an even more specific name
          if result[:shredout] &&
              subdivision.dig(:subcategories) &&
              subdivision.dig(:subcategories, result[:shredout])
            return subdivision.dig(:subcategories, result[:shredout], :name)
          end

          # Return the subdivision name if no shredout match
          return subdivision.dig(:name)
        end

        # Return the base name if no subdivision match
        return loaded_data.dig(base_code, :name)
      end

      # Return a default if no match found
      "Unknown"
    end
  end
end
