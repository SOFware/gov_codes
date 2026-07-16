# frozen_string_literal: true

require_relative "../patterns"

module GovCodes
  module Dafecd
    module RiSdi
      # Per-publication configuration for the RI/SDI extractor.
      #
      # The DAFECD (enlisted) and DAFOCD (officer) directories publish their
      # Reporting Identifiers (RI) and Special Duty Identifiers (SDI) in the same
      # two record formats (the SDI "card" and the flat numbered RI list). They
      # differ only in the code SHAPE (enlisted codes are 5 chars, "8A200";
      # officer codes are 4 chars, "80C0"), the running page header, and where the
      # combined artifact is written. A Config captures exactly those differences
      # and is injected into every stage.
      class Config
        # Enlisted RI/SDI code: a digit, a letter, three digits (8A200, 9Z200,
        # 5I000, 5Z700). Space Force RI reuses the same shape.
        ENLISTED_CODE = /\d[A-Z]\d{3}/

        # Officer RI/SDI code: two digits, a letter, a level digit (80C0, 90G0).
        # The trailing character is a DIGIT — never "X" — which is what rejects
        # the academic CIP codes ("05XX", "14.10XX") that share the officer RI
        # list's page real estate.
        OFFICER_CODE = /\d\d[A-Z]\d/

        DAFECD_HEADER = /^\s*DAFECD,\s+\d/
        DAFOCD_HEADER = /^\s*DAFOCD,\s+\d/

        # Both directories head the shredout table with "Suffix ... Portion of
        # <AFS|RI> to Which Related"; the leading "Suffix <word>" is common to
        # every variant, so the existing header regex matches them all.
        SHREDOUT_HEADER = /Suffix\s+\w/

        class << self
          def dafecd
            @dafecd ||= new(
              id: :dafecd,
              directory_name: "Department of the Air Force Enlisted Classification Directory",
              code: ENLISTED_CODE,
              header: DAFECD_HEADER,
              release_dir: "dafecd",
              # Trailing parentheticals that abbreviate an embedded organization
              # or a sub-phrase — NOT the identifier's own name — and so must not
              # ship as the record's acronym. See the acronym classification in
              # the extractor report. (SWMS/AFSPECWAR/MEPCOM/etc. are mid-title or
              # length-excluded and never captured, so they need no listing here.)
              acronym_exclusions: %i[9B100 9H100 9M400],
              # AF SDI -> AF RI -> (skip SFSC) -> SF SDI -> SF RI
              sections: [
                {kind: :sdi, force: :af, header: /^\s*SPECIALDUTY IDENTIFIERS \(SDI\)/},
                {kind: :ri, force: :af, header: /^\s*AIR FORCE REPORTING IDENTIFIERS \(RI\)/},
                {kind: :skip, force: :sf, header: /^\s*SPACE FORCE SPECIALTY CODES \(SFSC\)/},
                {kind: :sdi, force: :sf, header: /^\s*SPACE FORCE SPECIAL ?DUTY IDENTIFIERS \(SDI\)/},
                {kind: :ri, force: :sf, header: /^\s*SPACE FORCE REPORTING IDENTIFIERS \(RI\)/}
              ]
            )
          end

          def dafocd
            @dafocd ||= new(
              id: :dafocd,
              directory_name: "Department of the Air Force Officer Classification Directory",
              code: OFFICER_CODE,
              header: DAFOCD_HEADER,
              release_dir: "dafocd",
              acronym_exclusions: [],
              # Officer SDI -> Officer RI (no AF/SF split in the officer directory)
              sections: [
                {kind: :sdi, force: :officer, header: /^\s*SPECIAL ?DUTY IDENTIFIERS \(SDI\)/},
                {kind: :ri, force: :officer, header: /^\s*REPORTING IDENTIFIERS \(RI\)/}
              ]
            )
          end

          def for(id)
            by_id = {dafecd: dafecd, dafocd: dafocd}
            by_id.fetch(id.to_sym) do
              raise ArgumentError,
                "unknown publication #{id.inspect}; valid options are #{by_id.keys.map(&:inspect).join(", ")}"
            end
          end
        end

        attr_reader :id, :directory_name, :code, :header, :shredout_header,
          :release_dir, :sections, :index_filename, :acronym_exclusions,
          :title_overrides_filename, :sdi_anchor, :sdi_inline_anchor, :ri_anchor, :cem

        def initialize(id:, directory_name:, code:, header:, release_dir:, sections:, acronym_exclusions:)
          @id = id
          @directory_name = directory_name
          @code = code
          @header = header
          @shredout_header = SHREDOUT_HEADER
          @release_dir = release_dir
          @sections = sections
          @acronym_exclusions = acronym_exclusions
          @index_filename = "ri.yml"
          # Human-verified de-glued titles, one file per publication, gated at
          # build time against the verbatim source (spacing/case only).
          @title_overrides_filename = "title_overrides/#{id}.yml"
          # A standalone SDI card anchor ("SDI 8A200") and an inline-title anchor
          # ("SDI 8L100,AirAdvisor - Basic"); group 1 is the code, group 2 (inline
          # only) the raw title text. The inline anchor's "SDI " keyword is
          # OPTIONAL: the officer Air Advisor cards (89A0-89I0) print as a bare
          # "CODE,Title" line with no prefix. False positives are still rejected
          # downstream by Title.real? (the inline "title" must start with a
          # capital/digit/paren, never a wrapped-prose lowercase continuation),
          # and the "^" anchor keeps the code at line start so mid-line codes
          # (e.g. "...10-4301V1, Air Advisor Training") never match.
          @sdi_anchor = /^\s*SDI\s+(#{code})\*?\s*$/
          @sdi_inline_anchor = /^\s*(?:SDI\s+)?(#{code})\*?,\s*(\S.*)$/
          # A flat-list RI anchor: a top-level list number, an optional decorative
          # star, then the code. Group 1 is the list number, group 2 the code,
          # group 3 the remainder of the line (title, possibly with a trailing
          # date). Tolerates a run of spaces or none after "<n>.", and a comma or
          # a bare space before the title.
          @ri_anchor =
            /^[ \t]*(\d{1,2})\.[ \t]*(?:#{Patterns::DECORATIVE}[ \t]*)*(#{code})\s*,?\s*(.*)$/
          # The one ladder record embedded in the enlisted AF SDI section
          # ("CEM Code 8G000", Premier Honor Guard) is handled by the AFSC
          # pipeline; the splitter uses this to isolate it from the cards.
          @cem = Patterns::CEM
          freeze
        end

        # The absolute path to this publication's RI/SDI title-overrides file.
        # Mirrors Publication#title_overrides_path so the shared TitleDegluer
        # (its .for/#override_for/.matches_source? API) loads from a Config too.
        def title_overrides_path
          File.expand_path(@title_overrides_filename, __dir__)
        end
      end
    end
  end
end
