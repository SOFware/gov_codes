require "strscan"
require_relative "releases"

module GovCodes
  module AFSC
    # Officer AFSCs resolved against the versioned DAFOCD release index. Mirrors
    # Enlisted: +find(code, as_of:)+ resolves the X-form specialty (e.g. :11BX)
    # or a literal bare code (e.g. :10C0) in the release in effect on +as_of+,
    # defaulting to today.
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

      CODES = {}
      private_constant :CODES

      Code = Data.define(
        :prefix,
        :career_group,
        :functional_area,
        :qualification_level,
        :qualification_level_number,
        :qualification_level_name,
        :shredout,
        :shredout_name,
        :specialty,
        :specialty_name,
        :specific_afsc,
        :name,
        :acronym,
        :effective_date
      )

      # Resolve an officer AFSC against the DAFOCD release in effect on +as_of+
      # (default: today). Returns nil when the code does not parse, when neither
      # the X-form specialty nor a literal bare code resolves in the release, or
      # when +as_of+ precedes the earliest shipped release (or no release has
      # taken effect yet).
      def self.find(code, as_of: nil)
        code = code.to_s
        # Key the memo on the RESOLVED release date so equivalent as_of values
        # (nil, the Date, its string form, any date in the same release window)
        # share one slot instead of growing unbounded for time-series callers.
        effective_date = Releases.effective_date_for(as_of: as_of, publication: Releases::OFFICER_PUBLICATION)
        CODES[[code, effective_date]] ||= begin
          result = Parser.new(code).parse

          # Return nil if parsing failed or required fields are missing
          return nil if result.reject { |_, v| v.nil? }.empty? ||
            result[:career_group].nil? ||
            result[:functional_area].nil? ||
            result[:qualification_level].nil? ||
            result[:specific_afsc].nil?

          index = Releases.officer_index(as_of: as_of)

          # Prefer the X-form specialty key (11B3 -> :11BX). Fall back to the
          # literal 4-char code for bare specialties keyed that way (:10C0, :62S0,
          # :63G0, :63S0). By design these bare-code specialties resolve ONLY via
          # their literal code -- there is no X-form ladder for them, so
          # find("10CX")/find("62SX")/find("63GX")/find("63SX") return nil while
          # find("10C0")/find("62S0")/find("63G0")/find("63S0") resolve.
          specialty = :"#{result[:career_group]}#{result[:functional_area]}X"
          if !index.key?(specialty) && index.key?(result[:specific_afsc])
            specialty = result[:specific_afsc]
          end

          entry = index[specialty]
          return nil unless entry

          result[:specialty] = specialty
          result[:specialty_name] = entry[:name]

          # Qualification-level title: numeric level (1-4) maps to the directory's
          # per-specialty title; a letter (X/Y/Z) or an absent level leaves it nil.
          result[:qualification_level_number] = nil
          result[:qualification_level_name] = nil
          qual = result[:qualification_level].to_s
          if qual.match?(/\d/)
            number = Integer(qual)
            result[:qualification_level_number] = number
            result[:qualification_level_name] = entry.dig(:qual_levels, number, :title)
          end

          # Shredout meaning, only when the directory documents this shredout.
          shredout = result[:shredout]
          shredout_name = shredout && entry.dig(:shredouts, shredout)
          result[:shredout_name] = shredout_name

          name = shredout_name || entry[:name]
          return nil if name.nil?
          result[:name] = name

          # Acronym: a documented shredout acronym wins for a shredded code;
          # otherwise the specialty acronym (which a consumer overlay may set).
          shredout_acronym = shredout && entry.dig(:shredout_acronyms, shredout)
          result[:acronym] = shredout_acronym || entry[:acronym]
          result[:effective_date] = effective_date

          Code.new(**result)
        end
      end

      # Resolve the officer specialty/shredout whose acronym matches +acronym+
      # (case-insensitive) in the release in effect on +as_of+. Searches both
      # specialty acronyms and shredout acronyms; a shredout match returns the
      # concrete shredded code (so "TACPO" resolves find("19ZXB")). First match
      # wins: entries are scanned in index order and, within an entry, the
      # specialty acronym is tried before its shredout acronyms. Returns nil when
      # no acronym in the resolved release matches (no leakage across dates).
      def self.find_by_acronym(acronym, as_of: nil)
        acronym = acronym.to_s.upcase
        return nil if acronym.empty?

        index = Releases.officer_index(as_of: as_of)
        index.each do |specialty, entry|
          return find(specialty.to_s, as_of: as_of) if entry[:acronym].to_s.upcase == acronym

          (entry[:shredout_acronyms] || {}).each do |shredout, acr|
            return find("#{specialty}#{shredout}", as_of: as_of) if acr.to_s.upcase == acronym
          end
        end
        nil
      end

      # Walk the resolved index emitting each specialty code and its
      # specialty+shredout combinations, returning the Codes matching +prefix+.
      def self.search(prefix, as_of: nil)
        prefix = prefix.to_s.upcase
        index = Releases.officer_index(as_of: as_of)

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

      # Clears the memoized lookups and resets the versioned release loader. The
      # +lookup+ keyword is accepted for interface parity with Enlisted/RI; the
      # versioned index is resolved from the load path at lookup time.
      def self.reset_data(lookup: $LOAD_PATH)
        Releases.reset!
        CODES.clear
      end
    end
  end
end
