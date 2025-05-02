require "strscan"
require "yaml"
require_relative "../data_loader"

puts "Loading enlisted.rb"

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

          # Scan for subdivision digit and combine with career field
          subdivision_digit = scanner.scan(/\d/)
          return result unless subdivision_digit
          result[:career_field_subdivision] = :"#{result[:career_field]}#{subdivision_digit}"

          # Scan for skill level
          skill_level = scanner.scan(/[\dX]/)
          return result unless skill_level
          result[:skill_level] = skill_level.to_sym

          # Scan for specific AFSC digit and combine with previous components
          specific_digit = scanner.scan(/\d/)
          return result unless specific_digit
          result[:specific_afsc] = :"#{result[:career_field_subdivision]}#{result[:skill_level]}#{specific_digit}"

          result[:subcategory] = result[:specific_afsc][2..4].to_sym

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

          return nil if result.reject { |_, v| v.nil? }.empty?

          # Find the name by recursively searching the codes hash
          name = find_name_recursive(result)

          # Add the name to the result
          result[:name] = name

          # Create a new Code object with the result
          Code.new(**result)
        end
      end
    end
  end
end
