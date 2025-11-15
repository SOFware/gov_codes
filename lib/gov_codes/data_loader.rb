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
      lookup_array = Array(lookup)
      return data if lookup_array.empty?

      # Add the gem's lib directory to the lookup path
      gem_lib_dir = File.expand_path("..", __dir__)
      lookup_paths = [gem_lib_dir] + lookup_array

      # Convert namespace to file path parts (e.g., "GovCodes::AFSC::Enlisted" -> ["gov_codes", "afsc", "enlisted.yml"])
      namespace_parts = name.split("::")
        .map { |part| part.gsub(/([A-Z])([a-z])/, '_\1\2').downcase.sub(/^_/, "") }
      namespace_parts[-1] = "#{namespace_parts[-1]}.yml"

      # Find all existing YAML files in lookup paths
      lookup_paths.filter_map do |dir|
        yaml_path = File.join(dir, *namespace_parts)
        yaml_path if File.exist?(yaml_path)
      end.uniq.each do |path|
        yaml_data = YAML.load_file(path, symbolize_names: true)
        data.merge!(yaml_data) if yaml_data.is_a?(Hash)
      rescue Psych::SyntaxError, TypeError
        # Handle invalid YAML gracefully
        next
      end

      data
    end

    def reset_data(lookup: $LOAD_PATH)
      remove_const(:DATA) if const_defined?(:DATA, false)
      const_set(:DATA, data(lookup:).freeze)
      remove_const(:CODES) if const_defined?(:CODES, false)
      const_set(:CODES, {})
    end

    def find_name_recursive(result)
      base_code = result[:career_field].to_sym
      base_data = self::DATA[base_code]
      return "Unknown" unless base_data

      # Try subcategory lookup if present
      if result[:subcategory]
        subdivision = base_data.dig(:subcategories, result[:subcategory])
        if subdivision
          # Try shredout lookup if present
          if result[:shredout]
            shredout_name = subdivision.dig(:subcategories, result[:shredout], :name)
            return shredout_name if shredout_name
          end
          return subdivision[:name] if subdivision[:name]
        end
      end

      base_data[:name] || "Unknown"
    end
  end
end
