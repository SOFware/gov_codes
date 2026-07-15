# frozen_string_literal: true

module GovCodes
  module Dafecd
    # Per-publication configuration for the classification-directory extractor.
    #
    # The DAFECD (enlisted) and DAFOCD (officer) directories share the same
    # extraction pipeline (RecordSplitter -> SpecialtyParser -> ShredoutParser ->
    # IndexBuilder) but differ in a handful of concrete details: the running
    # header, the shape of a skill/qualification ladder line, whether standalone
    # single-code records and CEM lines exist, how the X-form specialty key is
    # derived, and where the release artifact is written.
    #
    # A Publication is an immutable value object capturing exactly those
    # differences. It is injected into every pipeline stage. The default
    # everywhere is +Publication.dafecd+, so the enlisted extraction is
    # byte-for-byte unchanged by the parameterization.
    class Publication
      # --- Enlisted (DAFECD) patterns ------------------------------------------
      # Running page header, e.g. "DAFECD, 31 Oct 25".
      DAFECD_HEADER = /^\s*DAFECD,\s+\d/

      # Skill-ladder line (group 1 = concrete 5-char AFSC, group 2 = skill-level
      # word). Tolerates the DAFECD's pdf-reader quirks (see Patterns::LADDER).
      DAFECD_LADDER = /
        ^\s*(?:AFSC\s+)?(\d[A-Z]\d\d\d)\*?
        (?:\s+or\s+\d[A-Z0-9]+)?
        ,?\s*
        (?:[A-Za-z][A-Za-z\/]*\s+){0,3}
        (Helper|Apprentice|Journeyman|Craftsman|
         Superintendent|Senior\s+Enlisted(?:\s+Leader)?|Entry)
        (?:\s*\([A-Z]{2,6}\))?
        (?:\s*AFSC)?
        \s*$
      /x

      # CEM (Chief Enlisted Manager) code line, e.g. "CEM Code 1A100*".
      DAFECD_CEM = /^\s*CEM Code\s+(\d[A-Z]\d00)\*?/

      # Inserts a boundary before an "AFSC <enlisted-code>" glued to a word.
      DAFECD_GLUED_AFSC = /(?<=[A-Za-z])(?=AFSC \d[A-Z]\d\d\d)/

      # The DAFECD's per-record change-date annotation.
      DAFECD_CHANGE_DATE = /\((?:Changed|Established|Effective)\s+(\d{1,2}\s+\w{3,9}\s+\d{2,4})\)/

      # The DAFECD shredout table header ("Suffix ... Primary Aircraft").
      DAFECD_SHREDOUT_HEADER = /Suffix\s+\w/

      # --- Officer (DAFOCD) patterns -------------------------------------------
      # Running page header, e.g. "DAFOCD, 31 Oct 25".
      DAFOCD_HEADER = /^\s*DAFOCD,\s+\d/

      # Qualification-ladder line (group 1 = concrete 4-char AFSC, group 2 =
      # free-form qualification title). The officer title vocabulary is open, so
      # the anchor relies on the CODE SHAPE (exactly 4 chars: two digits, a
      # letter, and a level digit 1-4) plus a SHORT title that ENDS the line AND
      # STARTS WITH AN UPPERCASE LETTER. Every real DAFOCD qualification title is
      # a proper label (Entry, Qualified, Aircraft Commander, Staff, ...), so the
      # uppercase-initial requirement rejects wrapped source PROSE that happens to
      # begin "AFSC <4-char-code>, <lowercase words>" (e.g. the real lines
      # "AFSC 14F3, but applied to developing" and "AFSC 42G3, current and
      # continuous"), which otherwise satisfied the code+short-title shape. It
      # also still rejects the 5-char shred-code / long-sentence prose mentions.
      # An optional leading/trailing "AFSC" absorbs the same pdf-reader glue the
      # enlisted ladder handles (e.g. "11G4, StaffAFSC").
      DAFOCD_LADDER = %r{
        ^\s*(?:AFSC\s+)?(\d\d[A-Z][1-4])\*?
        ,\s*
        ([A-Z][A-Za-z/\ ]{0,44}?)
        (?:\s*AFSC)?
        \s*$
      }x

      # A standalone single-code officer record, e.g. "AFSC 10C0". These carry a
      # title/date/sections but no ladder; each is a full record keyed by the
      # literal code.
      DAFOCD_BARE_CODE = /^\s*AFSC\s+(\d\d[A-Z][0-9X])\s*$/

      # Inserts a boundary before an "AFSC <officer-code>" glued to a word.
      DAFOCD_GLUED_AFSC = /(?<=[A-Za-z])(?=AFSC \d\d[A-Z][1-4])/

      # The DAFOCD's per-record change-date annotation. Tolerant of the officer
      # directory's glued day/month ("30Apr 23") and of a trailing second date
      # ("30Apr 14, Effective 25 Oct 13"): the first annotation is captured.
      DAFOCD_CHANGE_DATE = /\((?:Changed|Established|Effective)\s+(\d{1,2}\s*\w{3,9}\s+\d{2,4})/

      # The DAFOCD shredout table header ("Suffix ... Portion of AFS to Which
      # Related").
      DAFOCD_SHREDOUT_HEADER = /Suffix\s+\w/

      class << self
        # @return [Publication] the enlisted directory configuration
        def dafecd
          @dafecd ||= new(
            id: :dafecd,
            directory_name: "Department of the Air Force Enlisted Classification Directory",
            header: DAFECD_HEADER,
            ladder: DAFECD_LADDER,
            bare_code: nil,
            cem: DAFECD_CEM,
            glued_afsc: DAFECD_GLUED_AFSC,
            change_date: DAFECD_CHANGE_DATE,
            shredout_header: DAFECD_SHREDOUT_HEADER,
            levels_key: :skill_levels,
            code_has_specific: true,
            captures_shredout_acronyms: false,
            acronym_exclusions: %i[1D7X2 1A8X0],
            release_dir: "dafecd",
            index_filename: "enlisted.yml",
            title_overrides_filename: "title_overrides.yml",
            shredout_overrides_filename: "shredout_overrides/dafecd.yml"
          )
        end

        # @return [Publication] the officer directory configuration
        def dafocd
          @dafocd ||= new(
            id: :dafocd,
            directory_name: "Department of the Air Force Officer Classification Directory",
            header: DAFOCD_HEADER,
            ladder: DAFOCD_LADDER,
            bare_code: DAFOCD_BARE_CODE,
            cem: nil,
            glued_afsc: DAFOCD_GLUED_AFSC,
            change_date: DAFOCD_CHANGE_DATE,
            shredout_header: DAFOCD_SHREDOUT_HEADER,
            levels_key: :qual_levels,
            code_has_specific: false,
            captures_shredout_acronyms: true,
            acronym_exclusions: [],
            release_dir: "dafocd",
            index_filename: "officer.yml",
            title_overrides_filename: "title_overrides/dafocd.yml",
            shredout_overrides_filename: "shredout_overrides/dafocd.yml"
          )
        end

        # Select the publication that matches +text+'s running header, defaulting
        # to enlisted.
        def detect(text)
          [dafocd, dafecd].find { |pub| pub.header.match?(text) } || dafecd
        end

        # Look a publication up by its id symbol (:dafecd / :dafocd).
        def for(id)
          by_id = {dafecd: dafecd, dafocd: dafocd}
          by_id.fetch(id.to_sym) do
            raise ArgumentError,
              "unknown publication #{id.inspect}; valid options are #{by_id.keys.map(&:inspect).join(", ")}"
          end
        end
      end

      attr_reader :id, :directory_name, :header, :ladder, :bare_code, :cem,
        :glued_afsc, :change_date, :shredout_header, :levels_key,
        :acronym_exclusions, :release_dir, :index_filename,
        :title_overrides_filename, :shredout_overrides_filename

      def initialize(id:, directory_name:, header:, ladder:, bare_code:, cem:,
        glued_afsc:, change_date:, shredout_header:, levels_key:,
        code_has_specific:, captures_shredout_acronyms:, acronym_exclusions:,
        release_dir:, index_filename:, title_overrides_filename:,
        shredout_overrides_filename:)
        @id = id
        @directory_name = directory_name
        @header = header
        @ladder = ladder
        @bare_code = bare_code
        @cem = cem
        @glued_afsc = glued_afsc
        @change_date = change_date
        @shredout_header = shredout_header
        @levels_key = levels_key
        @code_has_specific = code_has_specific
        @captures_shredout_acronyms = captures_shredout_acronyms
        @acronym_exclusions = acronym_exclusions
        @release_dir = release_dir
        @index_filename = index_filename
        @title_overrides_filename = title_overrides_filename
        @shredout_overrides_filename = shredout_overrides_filename
        freeze
      end

      # Whether this publication extracts shredout-level acronyms (officer).
      def captures_shredout_acronyms?
        @captures_shredout_acronyms
      end

      # The X-form specialty key for a ladder group's concrete codes.
      #   enlisted: 1A172,1A152,... -> :1A1X2  (X at the level digit, specific kept)
      #   officer:  11B4,11B3,...   -> :11BX    (X at the level digit, no specific)
      # Returns nil when no codes are given.
      def specialty_key(codes)
        return nil if codes.empty?
        basis = specialty_basis(codes)
        prefix = basis.first[0, 3]
        @code_has_specific ? :"#{prefix}X#{most_common_specific(basis)}" : :"#{prefix}X"
      end

      # The career-field key (first two chars of the basis code).
      def career_field(codes)
        return nil if codes.empty?
        :"#{specialty_basis(codes).first[0, 2]}"
      end

      # The absolute path to this publication's title-overrides file.
      def title_overrides_path
        File.expand_path(@title_overrides_filename, __dir__)
      end

      # The absolute path to this publication's shredout-overrides file.
      def shredout_overrides_path
        File.expand_path(@shredout_overrides_filename, __dir__)
      end

      private

      # The ladder codes that define the specialty. Enlisted: a subdivision
      # superintendent (skill digit 9) carries a specific digit of 0, so the
      # specialty is defined by its non-superintendent levels. Officer: all ladder
      # codes share the same three-char family, so every code is basis.
      def specialty_basis(codes)
        return codes unless @code_has_specific
        non_super = codes.reject { |code| code[3] == "9" }
        non_super.empty? ? codes : non_super
      end

      # The most frequent specific (5th) digit among the basis codes (enlisted).
      def most_common_specific(basis)
        basis.map { |code| code[4] }.group_by(&:itself).max_by { |_, v| v.size }.first
      end
    end
  end
end
