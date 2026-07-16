require "strscan"
require_relative "releases"

module GovCodes
  module AFSC
    # Reporting Identifiers (RI) and Special Duty Identifiers (SDI), resolved
    # against the versioned classification-directory release indexes. RI/SDI
    # codes live in BOTH directories under two different code grammars:
    #
    #   Enlisted (DAFECD), 5-char:  \d[A-Z]\d{3}[A-Z]?   e.g. 9Z200, 8R300A
    #   Officer  (DAFOCD), 4-char:  \d{2}[A-Z]\d[A-Z]?   e.g. 90G0,  92T1
    #
    # A single +find+ entry point dispatches by shape to the matching
    # publication's ri.yml index (Releases.ri_index). Entries share the shape of
    # enlisted/officer specialty records (:name, :acronym, :shredouts,
    # :shredout_acronyms), so shredout suffixes and acronyms resolve exactly as
    # they do for Enlisted/Officer.
    module RI
      class Parser
        def initialize(code)
          @code = code.to_s
        end

        # Try the 5-char enlisted shape first, then the 4-char officer shape.
        # Both shapes are mutually exclusive (an enlisted code's 2nd char is a
        # letter; an officer code's 2nd char is a digit), so at most one matches.
        # The result carries the decomposed fields plus the :publication whose
        # index should resolve the name; all nil when neither shape parses.
        def parse
          parse_enlisted || parse_officer || empty_result
        end

        private

        def empty_result
          {
            career_group: nil,
            career_field: nil,
            identifier: nil,
            suffix: nil,
            specific_ri: nil,
            publication: nil
          }
        end

        # Enlisted shape: career_group (1 digit), career_field (digit+letter,
        # e.g. "9Z"), identifier (3 digits), optional 1-letter suffix.
        def parse_enlisted
          scanner = StringScanner.new(@code)
          career_group = scanner.scan(/\d/) or return nil
          field_letter = scanner.scan(/[A-Z]/) or return nil
          identifier = scanner.scan(/\d{3}/) or return nil
          suffix = scanner.scan(/[A-Z]/)
          return nil unless scanner.eos?

          career_field = :"#{career_group}#{field_letter}"
          {
            career_group: career_group.to_sym,
            career_field: career_field,
            identifier: identifier.to_sym,
            suffix: suffix&.to_sym,
            specific_ri: :"#{career_field}#{identifier}",
            publication: Releases::ENLISTED_PUBLICATION
          }
        end

        # Officer shape: same grammar as an officer AFSC (2-digit career group +
        # functional-area letter + 1-digit qualification level). There is no
        # natural 3-digit identifier here, so these codes are mapped onto the
        # SAME Code struct with the closest-matching semantics:
        #   career_group  the 2-digit prefix   (e.g. :"90")
        #   career_field  2-digit + letter     (e.g. :"90G")
        #   identifier    the trailing digit   (e.g. :"0")  <- 1 digit, not 3;
        #                                                       intentional, not a bug
        #   specific_ri   the full 4-char code (e.g. :"90G0")
        def parse_officer
          scanner = StringScanner.new(@code)
          career_group = scanner.scan(/\d{2}/) or return nil
          field_letter = scanner.scan(/[A-Z]/) or return nil
          identifier = scanner.scan(/\d/) or return nil
          suffix = scanner.scan(/[A-Z]/)
          return nil unless scanner.eos?

          career_field = :"#{career_group}#{field_letter}"
          {
            career_group: career_group.to_sym,
            career_field: career_field,
            identifier: identifier.to_sym,
            suffix: suffix&.to_sym,
            specific_ri: :"#{career_field}#{identifier}",
            publication: Releases::OFFICER_PUBLICATION
          }
        end
      end

      CODES = {}
      private_constant :CODES

      Code = Data.define(
        :career_group,
        :career_field,
        :identifier,
        :suffix,
        :specific_ri,
        :name,
        :acronym,
        :effective_date
      )

      # Resolve an RI/SDI code against the release in effect on +as_of+ (default:
      # today). Dispatches by code shape to the enlisted (DAFECD) or officer
      # (DAFOCD) ri.yml index. Returns nil when the code parses as neither shape,
      # when the resolved index lacks the code, or when +as_of+ precedes the
      # earliest shipped release for the relevant publication.
      def self.find(code, as_of: nil)
        code = code.to_s
        parsed = Parser.new(code).parse
        publication = parsed[:publication]
        return nil unless publication

        # Key the memo on the RESOLVED release date so equivalent as_of values
        # (nil, the Date, its string form) share one slot.
        effective_date = Releases.effective_date_for(as_of: as_of, publication: publication)
        CODES[[code, effective_date]] ||= begin
          index = Releases.ri_index(as_of: as_of, publication: publication)
          entry = index[parsed[:specific_ri]]
          return nil unless entry

          suffix = parsed[:suffix]
          # Shredout suffix meaning, only when the directory documents it.
          shredout_name = suffix && entry.dig(:shredouts, suffix)
          name = shredout_name || entry[:name]
          return nil if name.nil?

          # A documented shredout acronym wins for a shredded code; otherwise the
          # entry's own acronym (which a consumer overlay may set).
          shredout_acronym = suffix && entry.dig(:shredout_acronyms, suffix)

          Code.new(
            career_group: parsed[:career_group],
            career_field: parsed[:career_field],
            identifier: parsed[:identifier],
            suffix: suffix,
            specific_ri: parsed[:specific_ri],
            name: name,
            acronym: shredout_acronym || entry[:acronym],
            effective_date: effective_date
          )
        end
      end

      # Resolve the RI/SDI code whose acronym matches +acronym+ (case-insensitive)
      # in the release in effect on +as_of+. Scans the enlisted index first, then
      # the officer index; within an entry the entry's own acronym is tried before
      # its shredout acronyms (a shredout match returns the concrete shredded
      # code). First match wins. Returns nil when no acronym in the resolved
      # release(s) matches (no leakage across document dates).
      def self.find_by_acronym(acronym, as_of: nil)
        acronym = acronym.to_s.upcase
        return nil if acronym.empty?

        [Releases::ENLISTED_PUBLICATION, Releases::OFFICER_PUBLICATION].each do |publication|
          index = Releases.ri_index(as_of: as_of, publication: publication)
          index.each do |code, entry|
            return find(code.to_s, as_of: as_of) if entry[:acronym].to_s.upcase == acronym

            (entry[:shredout_acronyms] || {}).each do |suffix, acr|
              return find("#{code}#{suffix}", as_of: as_of) if acr.to_s.upcase == acronym
            end
          end
        end
        nil
      end

      # Walk both publications' RI/SDI indexes for the release in effect on
      # +as_of+, emitting each base code and its shredout-suffixed combinations,
      # and return the Codes whose code starts with +prefix+.
      def self.search(prefix, as_of: nil)
        prefix = prefix.to_s.upcase

        codes = []
        [Releases::ENLISTED_PUBLICATION, Releases::OFFICER_PUBLICATION].each do |publication|
          index = Releases.ri_index(as_of: as_of, publication: publication)
          index.each do |code, entry|
            code_str = code.to_s
            codes << code_str
            (entry[:shredouts] || {}).each_key do |suffix|
              codes << "#{code_str}#{suffix}"
            end
          end
        end

        codes.select { |code| code.start_with?(prefix) }
          .map { |code| find(code, as_of: as_of) }
          .compact
      end

      # Clears the memoized lookups and resets the versioned release loader. The
      # +lookup+ keyword is accepted for interface parity with Enlisted/Officer;
      # the versioned index is resolved from the load path at lookup time.
      def self.reset_data(lookup: $LOAD_PATH)
        Releases.reset!
        CODES.clear
      end
    end
  end
end
