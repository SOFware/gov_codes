require "strscan"
require "yaml"
require_relative "../data_loader"

module GovCodes
  module AFSC
    # Reporting Identifiers (RI) and Special Duty Identifiers (SDI)
    # These codes follow a different format than standard AFSCs:
    # - Career field: digit + letter (e.g., "9Z", "8A")
    # - Identifier: 3 digits (e.g., "200", "400")
    # - Optional suffix: letter (e.g., "A", "B")
    #
    # Examples: 9Z200, 8A400, 8G000B, 8R300A
    module RI
      class Parser
        def initialize(code)
          @code = code
        end

        def parse
          scanner = StringScanner.new(@code.to_s)
          result = {
            career_group: nil,
            career_field: nil,
            identifier: nil,
            suffix: nil,
            specific_ri: nil
          }

          # Scan for career group (single digit)
          career_group = scanner.scan(/\d/)
          return result unless career_group
          result[:career_group] = career_group.to_sym

          # Scan for career field letter
          career_field_letter = scanner.scan(/[A-Z]/)
          return result unless career_field_letter
          result[:career_field] = :"#{career_group}#{career_field_letter}"

          # Scan for identifier (3 digits)
          identifier = scanner.scan(/\d{3}/)
          return result unless identifier
          result[:identifier] = identifier.to_sym

          # Build specific RI code
          result[:specific_ri] = :"#{result[:career_field]}#{identifier}"

          # Scan for optional suffix (letter)
          suffix = scanner.scan(/[A-Z]/)
          result[:suffix] = suffix&.to_sym

          # Check if we've reached the end of the string
          return result unless scanner.eos?

          result
        end
      end

      extend GovCodes::DataLoader

      DATA = data

      Code = Data.define(
        :career_group,
        :career_field,
        :identifier,
        :suffix,
        :specific_ri,
        :name
      )

      def self.find_name_recursive(result)
        name = nil
        data = DATA

        career_field = result[:career_field]
        identifier = result[:identifier]
        suffix = result[:suffix]

        # Look for the career field (e.g., "9Z", "8A")
        if data[career_field]
          field_data = data[career_field]

          # Career field has name and subcategories
          if field_data.is_a?(Hash) && field_data[:subcategories]
            subcats = field_data[:subcategories]

            # Look for the identifier (e.g., "200", "400")
            if subcats[identifier]
              identifier_data = subcats[identifier]

              if identifier_data.is_a?(Hash)
                name = identifier_data[:name]

                # Look for suffix if present
                if suffix && identifier_data[:subcategories]
                  suffix_data = identifier_data[:subcategories][suffix]
                  name = suffix_data if suffix_data.is_a?(String)
                  name = suffix_data[:name] if suffix_data.is_a?(Hash)
                end
              else
                # Simple string value
                name = identifier_data
              end
            end
          end
        end

        name || "Unknown"
      end

      def self.find(code)
        code = code.to_s
        CODES[code] ||= begin
          parser = Parser.new(code)
          result = parser.parse

          # Return nil if parsing failed or required fields are missing
          return nil if result.reject { |_, v| v.nil? }.empty? ||
            result[:career_group].nil? ||
            result[:career_field].nil? ||
            result[:identifier].nil? ||
            result[:specific_ri].nil?

          # Find the name by recursively searching the codes hash
          name = find_name_recursive(result)

          # Return nil if name is "Unknown" (code not in data)
          return nil if name == "Unknown"

          # Add the name to the result
          result[:name] = name

          Code.new(**result)
        end
      end

      def self.reset_data(lookup: $LOAD_PATH)
        remove_const(:DATA) if const_defined?(:DATA)
        const_set(:DATA, data(lookup:))
        CODES.clear
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
