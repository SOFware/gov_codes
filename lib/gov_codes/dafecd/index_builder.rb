# frozen_string_literal: true

require_relative "patterns"
require_relative "record_splitter"
require_relative "specialty_parser"
require_relative "shredout_parser"
require_relative "title_degluer"

module GovCodes
  module Dafecd
    # Assembles parsed DAFECD records into a specialty-keyed index.
    #
    # Verification gate (DEC-003) — read this before trusting "0 unverified".
    # The gate confirms that every value emitted into the index appears verbatim
    # in the source text. For the CURRENT purely-deterministic extraction every
    # emitted code is a verbatim slice of the source, so the gate is guaranteed
    # to pass — "0 unverified" is a tautology here, NOT evidence of correctness.
    # The gate earns its keep as a REGRESSION GUARD for future value-transforming
    # steps (notably the C.2 title de-gluer, whose invariant is "the de-glued
    # title equals its source with only spaces changed"). Such a transform
    # registers the values it emits via the #emitted_values_to_verify hook, and
    # the gate flags any that are not grounded in the source.
    #
    # Drops are surfaced, never hidden: any record that carries a specialty
    # signal (a CEM code) but yields zero parsed ladder codes is collected in
    # #dropped_records with a reason. The invariant
    # records_split == index.size + merged_count + dropped_records.size holds.
    #
    # Title de-gluing: a TitleDegluer supplies verified clean titles (see
    # TitleDegluer). Each applied override is checked against the raw source
    # title via the de-gluing invariant (spacing/case only); drift lands in
    # #unverified_titles and must fail the build. Specialties without an override
    # keep the auto-titlecased name and are listed in #specialties_needing_deglue.
    class IndexBuilder
      # A specialty acronym is a trailing parenthetical whose sole token is an
      # uppercase abbreviation, e.g. "... (TACP)" -> TACP. Only trailing parens
      # qualify; a mid-title paren ("... (SERE) Specialist") is prose, not the
      # specialty's acronym.
      ACRONYM_PATTERN = /\(([A-Z][A-Z0-9]{1,7})\)\s*\z/

      # Specialties whose trailing parenthetical is a phrase-abbreviation, NOT a
      # specialty acronym, and so must NOT be emitted as :acronym:
      #   1D7X2 "... Electromagnetic Activities (EMA)"  -- abbreviates the phrase
      #   1A8X0 "... Surveillance and Reconnaissance (ISR)" -- abbreviates ISR
      # Both are excluded by decision (Task 1 finding); their curated specialty
      # acronyms, if any, come from the consumer overlay, never the source title.
      ACRONYM_EXCLUSIONS = %i[1D7X2 1A8X0].freeze

      def initialize(source_text, degluer: TitleDegluer.empty)
        @source_text = source_text
        @degluer = degluer
        @index = nil
        @unverified_codes = nil
      end

      # @return [Hash{Symbol=>Hash}] X-form specialty => index entry
      def build
        @index = {}
        @unverified_codes = []
        @unverified_titles = []
        @unverified_acronyms = []
        @needs_deglue = []
        @dropped_records = []
        @merged_count = 0

        records = RecordSplitter.new(@source_text).records
        @records_split = records.size

        records.each do |record|
          header = SpecialtyParser.new(record).parse
          specialty = header[:specialty]

          if specialty.nil?
            @dropped_records << drop_descriptor(record)
            next
          end

          entry = build_entry(header, ShredoutParser.new(record).parse)
          @merged_count += 1 if @index.key?(specialty)
          merge_entry(specialty, entry)
        end

        @index.each do |specialty, entry|
          apply_override(specialty, entry)
          capture_acronym(specialty, entry)
          verify(entry)
        end
        @index
      end

      # Values emitted into the index that could NOT be found verbatim in the
      # source. Empty by construction for the current deterministic extraction;
      # non-empty means a transform (e.g. the de-gluer) emitted an ungrounded
      # value. See the class docstring.
      def unverified_codes
        build if @unverified_codes.nil?
        @unverified_codes
      end

      # Applied title overrides that violate the de-gluing invariant (their
      # letters/digits/punctuation differ from the raw source title), each a
      # Hash of {specialty:, applied:, raw_title:, reason:}. Non-empty means a
      # stale/incorrect override; the build must fail. See #unverified?.
      def unverified_titles
        build if @unverified_titles.nil?
        @unverified_titles
      end

      # Specialties that have an auto-titlecased name but no verified override
      # (i.e. still need de-gluing). Should be empty once every specialty is
      # covered; kept for robustness across future entity types.
      def specialties_needing_deglue
        build if @needs_deglue.nil?
        @needs_deglue
      end

      # Emitted :acronym values that could NOT be found (whitespace/case
      # tolerant) in their specialty's raw source title. Non-empty means a
      # drifting/hallucinated acronym; the build must fail. See #unverified?.
      def unverified_acronyms
        build if @unverified_acronyms.nil?
        @unverified_acronyms
      end

      # True if any emitted value (code, applied title, or acronym) failed
      # verification. The CLI must fail the build when this is true.
      def unverified?
        unverified_codes.any? || unverified_titles.any? || unverified_acronyms.any?
      end

      # Records that carried a specialty signal but produced no ladder codes,
      # each a Hash of {cem_code:, first_line:, reason:}. Surfaced so drops can
      # never hide (C1).
      def dropped_records
        build if @dropped_records.nil?
        @dropped_records
      end

      # Number of records the splitter produced.
      def records_split
        build if @records_split.nil?
        @records_split
      end

      # Number of records that merged into an already-seen specialty.
      def merged_count
        build if @merged_count.nil?
        @merged_count
      end

      # The verification-gate predicate: does +value+ appear verbatim in source?
      def verified?(value)
        @source_text.include?(value.to_s)
      end

      # Specialties whose title could not be extracted (for the coverage report).
      def specialties_missing_title
        build if @index.nil?
        @index.select { |_, e| e[:name].nil? || e[:name].empty? }.keys
      end

      # Specialties with no shredout table (for the coverage report). This is a
      # normal condition for many specialties, not an error.
      def specialties_without_shredouts
        build if @index.nil?
        @index.select { |_, e| e[:shredouts].empty? }.keys
      end

      # Specialties whose title is flagged as a probable pdf-reader glue artifact
      # (heuristic), deferred to the C.2 despacer.
      def glued_titles
        build if @index.nil?
        @index.select { |_, e| e[:glued_title] }.transform_values { |e| e[:name] }
      end

      # Full title inventory for the de-gluing step: every specialty with its
      # current (title-cased) name and the raw pre-titlecase source title.
      # @return [Array<Hash>] {specialty:, name:, raw_title:, glued:}
      def title_inventory
        build if @index.nil?
        @index.sort_by { |k, _| k.to_s }.map do |specialty, e|
          {specialty: specialty, name: e[:name], raw_title: e[:raw_title], glued: e[:glued_title]}
        end
      end

      private

      # Describe a dropped record for the accounting report.
      def drop_descriptor(record)
        cem = record[Patterns::CEM, 1]
        first_line = record.lines.map(&:strip).reject(&:empty?).first
        reason =
          if cem
            "CEM code present but no skill-ladder AFSC lines (career-field CEM manager)"
          else
            "no CEM code and no skill-ladder AFSC lines"
          end
        {cem_code: cem, first_line: first_line, reason: reason}
      end

      def build_entry(header, shredouts)
        {
          name: header[:name],
          raw_title: header[:raw_title],
          career_field: header[:career_field],
          cem_code: header[:cem_code],
          changed_date: header[:changed_date],
          skill_levels: header[:skill_levels],
          shredouts: shredouts,
          glued_title: header[:glued_title]
        }
      end

      # Merge a re-encountered specialty (e.g. a record split by a page break)
      # rather than silently overwriting it.
      def merge_entry(specialty, entry)
        existing = @index[specialty]
        if existing.nil?
          @index[specialty] = entry
          return
        end

        existing[:name] ||= entry[:name]
        existing[:raw_title] ||= entry[:raw_title]
        existing[:career_field] ||= entry[:career_field]
        existing[:cem_code] ||= entry[:cem_code]
        existing[:changed_date] ||= entry[:changed_date]
        existing[:skill_levels] = entry[:skill_levels].merge(existing[:skill_levels])
        existing[:shredouts] = entry[:shredouts].merge(existing[:shredouts])
        existing[:glued_title] ||= entry[:glued_title]
      end

      # Apply a verified de-glued title override, enforcing the invariant that an
      # override differs from the raw source title only in spacing/case. Drift is
      # recorded (never silently applied); a missing override keeps the auto
      # title and is flagged for de-gluing.
      def apply_override(specialty, entry)
        override = @degluer.override_for(specialty)

        if override.nil?
          @needs_deglue << specialty if entry[:name]
          return
        end

        if TitleDegluer.matches_source?(override, entry[:raw_title])
          entry[:name] = override
        else
          @unverified_titles << {
            specialty: specialty,
            applied: override,
            raw_title: entry[:raw_title],
            reason: "override differs from source title by more than spacing/case"
          }
        end
      end

      # Capture the specialty acronym from the (de-glued) name: a trailing
      # parenthetical uppercase token. Excluded specialties (phrase
      # abbreviations, not specialty acronyms) never receive an :acronym. The
      # name is left unchanged; it retains the parenthetical.
      def capture_acronym(specialty, entry)
        return if ACRONYM_EXCLUSIONS.include?(specialty)
        name = entry[:name]
        return if name.nil?

        match = name.match(ACRONYM_PATTERN)
        entry[:acronym] = match[1] if match
      end

      def verify(entry)
        entry[:skill_levels].each_value do |level|
          @unverified_codes << level[:code] unless verified?(level[:code])
        end
        cem = entry[:cem_code]
        @unverified_codes << cem if cem && !verified?(cem)
        emitted_values_to_verify(entry).each do |value|
          @unverified_codes << value unless verified?(value)
        end
        verify_acronym(entry)
      end

      # The acronym gate (DEC-003): an emitted :acronym must appear as a
      # parenthetical `(ACRONYM)` in the specialty's raw source title -- not
      # merely as some substring of it -- under the same whitespace/case
      # tolerance the de-glue gate uses. A drifting/absent acronym is unverified.
      def verify_acronym(entry)
        acronym = entry[:acronym]
        return if acronym.nil?

        source = TitleDegluer.norm(entry[:raw_title])
        @unverified_acronyms << acronym unless source.include?(TitleDegluer.norm("(#{acronym})"))
      end

      # Hook for future value-transforming steps (e.g. the C.2 title de-gluer):
      # return the additional values the transform emits into this entry so the
      # gate can confirm each is grounded in the source. Default: none.
      def emitted_values_to_verify(entry)
        []
      end
    end
  end
end
