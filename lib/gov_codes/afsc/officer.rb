require "strscan"
require "yaml"
require_relative "../data_loader"

module GovCodes
  module AFSC
    module Officer
      class Parser
        def initialize(code)
          @code = code
        end

        def parse
          scanner = StringScanner.new(@code.to_s)
          result = {
            prefix: nil,
            career_group: nil,
            functional_area: nil,
            qualification_level: nil,
            shredout: nil,
            specific_afsc: nil
          }

          # Scan for prefix (optional)
          result[:prefix] = scanner.scan(/[A-Z]/)

          # Scan for career group (two digits)
          career_group = scanner.scan(/\d{2}/)
          return result unless career_group
          result[:career_group] = career_group.to_sym

          # Scan for functional area (uppercase letter)
          functional_area = scanner.scan(/[A-Z]/)
          return result unless functional_area
          result[:functional_area] = functional_area.to_sym

          # Scan for qualification level (digit 0-4 or letter X-Z)
          qualification_level = scanner.scan(/[0-4A-Z]/)
          return result unless qualification_level
          result[:qualification_level] = qualification_level.to_sym

          # Build specific AFSC
          result[:specific_afsc] = :"#{result[:career_group]}#{result[:functional_area]}#{result[:qualification_level]}"

          # Scan for shredout (optional)
          shredout = scanner.scan(/[A-Z]/)
          result[:shredout] = shredout&.to_sym

          # Check if we've reached the end of the string
          return result unless scanner.eos?

          result
        end
      end

      extend GovCodes::DataLoader

      DATA = data

      Code = Data.define(
        :prefix,
        :career_group,
        :functional_area,
        :qualification_level,
        :shredout,
        :specific_afsc,
        :name
      )

      def self.find_name_recursive(result)
        name = nil
        data = DATA

        # For officer codes, build the lookup key from career group + functional area + qual level
        # like "11BX" where "11" is career group, "B" is functional area, "X" is qual level
        career_group = result[:career_group].to_s
        functional_area = result[:functional_area].to_s
        qual_level = result[:qualification_level].to_s
        combined_key = :"#{career_group}#{functional_area}#{qual_level}"

        # Look for the full code (e.g., "11BX", "11MX")
        if data[combined_key]
          name = data[combined_key][:name]
          data = data[combined_key][:subcategories]

          # Then look for shredout
          if data && result[:shredout]
            shred = result[:shredout]
            # Try Symbol first (most shredouts are letters), then Integer, then String
            lookup_value = data[shred] || data[shred.to_s.to_i] || data[shred.to_s]
            if lookup_value
              name = lookup_value.is_a?(Hash) ? (lookup_value[:name] || name) : (lookup_value || name)
            end
          end
        end

        name || "Unknown"
      end

      def self.find(code)
        code = code.to_s
        parser = Parser.new(code)
        result = parser.parse

        return nil if result.reject { |_, v| v.nil? }.empty?

        # Find the name by recursively searching the codes hash
        name = find_name_recursive(result)

        # Add the name to the result
        result[:name] = name

        Code.new(**result)
      end

      def self.search(prefix)
        results = []
        prefix = prefix.to_s.upcase
        collect_codes_recursive(DATA, "", prefix, results)
        results.map { |code| find(code) }.compact
      end

      def self.collect_codes_recursive(data, current_code, prefix, results)
        return unless data.is_a?(Hash)

        data.each do |key, value|
          code = "#{current_code}#{key}"

          if value.is_a?(Hash) && value[:name]
            # This is a node with a name and possibly subcategories
            results << code if code.start_with?(prefix)
            collect_codes_recursive(value[:subcategories], code, prefix, results) if value[:subcategories]
          elsif value.is_a?(String)
            # This is a leaf node (simple string value)
            results << code if code.start_with?(prefix)
          elsif value.is_a?(Hash)
            # Nested subcategories without a name at this level
            collect_codes_recursive(value, current_code, prefix, results)
          end
        end
      end
    end
  end
end
