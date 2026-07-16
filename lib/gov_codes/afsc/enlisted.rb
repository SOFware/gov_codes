require "strscan"
require_relative "releases"

module GovCodes
  module AFSC
    module Enlisted
      SKILL_LEVELS = {
        1 => "Helper",
        3 => "Apprentice",
        5 => "Journeyman",
        7 => "Craftsman",
        9 => "Superintendent"
      }.freeze

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
            skill_level_number: nil,
            skill_level_name: nil,
            specialty: nil,
            specialty_name: nil,
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

          # Scan for skill level: an X placeholder OR a concrete digit.
          # NOTE: any digit is accepted here for now; validating that it is a
          # real skill level (1/3/5/7/9) is deferred to Phase C.
          skill_char = scanner.scan(/[A-Z0-9]/)
          return result unless skill_char
          result[:skill_level] = skill_char.to_sym

          # Concrete skill level -> numeric level + standard title
          if skill_char.match?(/\d/)
            result[:skill_level_number] = Integer(skill_char)
            result[:skill_level_name] = SKILL_LEVELS[result[:skill_level_number]]
          end

          # Scan for the specific AFSC digit
          specific_digit = scanner.scan(/\d/)
          return result unless specific_digit

          # Normalize to the X-form specialty key regardless of concrete skill level
          result[:subcategory] = :"#{subdivision_digit}X#{specific_digit}"
          result[:specialty] = :"#{result[:career_field_subdivision]}X#{specific_digit}"

          # specific_afsc preserves the code exactly as entered (concrete or generic)
          result[:specific_afsc] = :"#{result[:career_field_subdivision]}#{skill_char}#{specific_digit}"

          # Scan for shredout (optional)
          result[:shredout] = scanner.scan(/[A-Z]/)&.to_sym

          # Check if we've reached the end of the string
          return result unless scanner.eos?

          result
        end
      end

      CODES = {}
      private_constant :CODES

      Code = Data.define(
        :prefix,
        :career_group,
        :career_field,
        :career_field_subdivision,
        :skill_level,
        :skill_level_number,
        :skill_level_name,
        :specialty,
        :specialty_name,
        :specific_afsc,
        :subcategory,
        :shredout,
        :shredout_name,
        :name,
        :acronym,
        :effective_date
      )

      # Resolve an enlisted AFSC against the DAFECD release in effect on +as_of+
      # (default: today). Returns nil when the code does not parse, when the
      # specialty is absent from the resolved release, or when +as_of+ precedes
      # the earliest shipped release (or no release has taken effect yet).
      def self.find(code, as_of: nil)
        code = code.to_s
        # Key the memo on the RESOLVED release date so equivalent as_of values
        # (nil, the Date, its string form, any date in the same release window)
        # share one slot instead of growing unbounded for time-series callers.
        effective_date = Releases.effective_date_for(as_of: as_of)
        CODES[[code, effective_date]] ||= begin
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

          # Resolve the specialty entry from the versioned, specialty-keyed index
          index = Releases.enlisted_index(as_of: as_of)
          entry = index[result[:specialty]]
          return nil unless entry

          specialty_name = entry[:name]

          # Skill-level title: prefer the directory's title for this specialty,
          # falling back to the universal enlisted skill-level map.
          if (number = result[:skill_level_number])
            result[:skill_level_name] = entry.dig(:skill_levels, number, :title) ||
              SKILL_LEVELS[number]
          end

          # Shredout meaning, only when the directory documents this shredout.
          shredout_name = result[:shredout] && entry.dig(:shredouts, result[:shredout])

          name = shredout_name || specialty_name
          return nil if name.nil?

          result[:shredout_name] = shredout_name
          result[:specialty_name] = specialty_name
          result[:name] = name
          # Specialty acronym from the resolved index entry (nil when absent).
          result[:acronym] = entry[:acronym]
          result[:effective_date] = effective_date

          Code.new(**result)
        end
      end

      # Resolve the enlisted specialty whose acronym matches +acronym+
      # (case-insensitive) in the release in effect on +as_of+. Returns the
      # generic (X-form) Code for that specialty, or nil when no specialty in the
      # resolved release carries the acronym. Acronyms come from the shipped,
      # source-verified data and any consumer overlay for that release, so the
      # match is scoped to that release (no leakage across document dates).
      def self.find_by_acronym(acronym, as_of: nil)
        acronym = acronym.to_s.upcase
        return nil if acronym.empty?

        index = Releases.enlisted_index(as_of: as_of)
        match = index.find { |_specialty, entry| entry[:acronym].to_s.upcase == acronym }
        return nil unless match

        find(match.first.to_s, as_of: as_of)
      end

      # Clears the memoized lookups and resets the versioned release loader.
      # The +lookup+ keyword is accepted for interface parity with Officer/RI;
      # the versioned index is resolved from the load path at lookup time.
      def self.reset_data(lookup: $LOAD_PATH)
        Releases.reset!
        CODES.clear
      end

      def self.search(prefix, as_of: nil)
        prefix = prefix.to_s.upcase
        index = Releases.enlisted_index(as_of: as_of)

        codes = []
        index.each do |specialty, entry|
          specialty_code = specialty.to_s
          codes << specialty_code
          (entry[:shredouts] || {}).each_key do |shredout|
            codes << "#{specialty_code}#{shredout}"
          end
        end

        codes.select { |code| code.start_with?(prefix) }
          .map { |code| find(code, as_of: as_of) }
          .compact
      end
    end
  end
end
