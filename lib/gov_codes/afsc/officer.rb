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
            shredout: nil
          }

          # Scan for prefix (optional)
          result[:prefix] = scanner.scan(/[A-Z]/)

          # Scan for career group (two digits)
          career_group = scanner.scan(/\d{2}/)
          return result unless career_group
          result[:career_group] = career_group

          # Scan for functional area (uppercase letter)
          functional_area = scanner.scan(/[A-Z]/)
          return result unless functional_area
          result[:functional_area] = functional_area

          # Scan for qualification level (digit 0-4)
          qualification_level = scanner.scan(/[0-4]/)
          return result unless qualification_level
          result[:qualification_level] = qualification_level

          # Scan for shredout (optional)
          result[:shredout] = scanner.scan(/[A-Z]/)

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
        :name
      )

      def self.find(code)
        code = code.to_s
        parser = Parser.new(code)
        result = parser.parse

        return nil if result.reject { |_, v| v.nil? }.empty?

        # Find the name from the codes data
        career_group = result[:career_group]
        functional_area = result[:functional_area]

        # Look up the name in the codes hash
        name = find_name(career_group, functional_area)

        # Add the name to the result
        result[:name] = name

        Code.new(**result)
      end
    end
  end
end
