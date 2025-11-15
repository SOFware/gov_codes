require "strscan"
require "yaml"
require_relative "../data_loader"

module GovCodes
  module AFSC
    module Enlisted
      class Parser
        def initialize(code)
          @code = code
        end

        def parse
          scanner = StringScanner.new(@code.to_s)
          result = {
            prefix: nil,
            career_group: nil,
            career_field: nil,
            career_field_subdivision: nil,
            skill_level: nil,
            specific_afsc: nil,
            subcategory: nil,
            shredout: nil
          }

          # Scan for prefix (optional)
          result[:prefix] = scanner.scan(/[A-Z]/)

          # Scan for career group (single digit)
          career_group = scanner.scan(/\d/)
          return result unless career_group
          result[:career_group] = career_group.to_sym

          # Scan for career field letter and combine with career group
          career_field_letter = scanner.scan(/[A-Z]/)
          return result unless career_field_letter
          result[:career_field] = :"#{career_group}#{career_field_letter}"

          # Scan for subdivision digit
          subdivision_digit = scanner.scan(/\d/)
          return result unless subdivision_digit
          result[:career_field_subdivision] = :"#{result[:career_field]}#{subdivision_digit}"

          # Scan for skill level letter (usually X)
          skill_level_letter = scanner.scan(/[A-Z]/)
          return result unless skill_level_letter
          result[:skill_level] = skill_level_letter.to_sym

          # Scan for skill level digit
          skill_level_digit = scanner.scan(/\d/)
          return result unless skill_level_digit

          # Subcategory is subdivision digit + letter + digit (e.g. '1X2')
          result[:subcategory] = :"#{subdivision_digit}#{skill_level_letter}#{skill_level_digit}"

          # Build specific AFSC
          result[:specific_afsc] = :"#{result[:career_field_subdivision]}#{skill_level_letter}#{skill_level_digit}"

          # Scan for shredout (optional)
          result[:shredout] = scanner.scan(/[A-Z]/)&.to_sym

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
        :career_field,
        :career_field_subdivision,
        :skill_level,
        :specific_afsc,
        :subcategory,
        :shredout,
        :name
      )

      def self.find(code)
        code = code.to_s
        CODES[code] ||= begin
          parser = Parser.new(code)
          result = parser.parse

          # Return nil if parsing failed or required fields are missing
          return nil if result.reject { |_, v| v.nil? }.empty? ||
            result[:career_group].nil? ||
            result[:career_field].nil? ||
            result[:career_field_subdivision].nil? ||
            result[:skill_level].nil? ||
            result[:specific_afsc].nil? ||
            result[:subcategory].nil?

          # Additional validation: check for invalid characters or too long codes
          return nil if code.length > 7 ||
            code.match?(/[^A-Z0-9]/)

          # Find the name by recursively searching the codes hash
          name = find_name_recursive(result)

          # Return nil if name is 'Unknown'
          return nil if name == "Unknown"

          # Add the name to the result
          result[:name] = name

          # Create a new Code object with the result
          Code.new(**result)
        end
      end

      def self.find_name_recursive(result)
        data = DATA

        # Career field (e.g., "9Z")
        cf = result[:career_field]&.to_sym
        return "Unknown" unless cf && data[cf]
        name = data[cf][:name]
        data = data[cf][:subcategories]

        # Subcategory (e.g., "0X1" from "9Z0X1")
        if data && result[:subcategory]
          sub = result[:subcategory].to_sym
          lookup_value = data[sub]
          if lookup_value
            if lookup_value.is_a?(Hash)
              name = lookup_value[:name] || name
              data = lookup_value[:subcategories]
            else
              # String value (leaf node)
              name = lookup_value
              data = nil
            end
          end
        end

        # Shredout (optional, e.g., :A)
        if data && result[:shredout]
          lookup_value = data[result[:shredout]]
          if lookup_value
            name = lookup_value.is_a?(Hash) ? (lookup_value[:name] || name) : (lookup_value || name)
          end
        end

        name || "Unknown"
      end
    end
  end
end
