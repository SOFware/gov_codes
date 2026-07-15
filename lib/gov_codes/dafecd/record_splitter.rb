# frozen_string_literal: true

require_relative "patterns"
require_relative "publication"
require_relative "text"

module GovCodes
  # Dev-only tooling that parses an official Department of the Air Force
  # classification directory (DAFECD enlisted / DAFOCD officer) PDF text into
  # structured data.
  #
  # These classes are NEVER required by the gem runtime. They are used offline
  # (via bin/extract_afsc_from_pdf.rb) to regenerate the versioned index when a
  # new directory is released.
  module Dafecd
    # Splits the full directory text into one string per specialty record.
    #
    # A specialty record begins at either:
    #   * a "CEM Code <code>" line (enlisted only), or
    #   * a bare standalone "AFSC <code>" line (officer single-code records), or
    #   * the first ladder line ("AFSC <code>, <title>") of a ladder group that
    #     is NOT immediately preceded (ignoring blank lines) by another ladder
    #     line, CEM line, or bare-code line.
    #
    # Running page headers ("DAFECD, <date>" / "DAFOCD, <date>") are stripped
    # before splitting. Behavior is publication-specific (injected Publication);
    # the default is the enlisted directory.
    class RecordSplitter
      # A lone title-case word on its own line (e.g. "Leader" left behind when
      # Text.split_glued_afsc splits "LeaderAFSC 1A178"). Such wrapped
      # continuations must not break a ladder group.
      CONTINUATION_WORD = /\A[A-Z][a-z]+\z/

      def initialize(text, publication: Publication.dafecd)
        @publication = publication
        @text = Text.split_glued_afsc(text, publication.glued_afsc)
      end

      # @return [Array<String>] one string per specialty record
      def records
        lines = @text.lines.reject { |line| line =~ @publication.header }

        records = []
        current = nil
        prev_meaningful_was_anchor = false

        lines.each do |line|
          is_ladder = line =~ @publication.ladder
          is_cem = @publication.cem && line =~ @publication.cem
          is_bare = @publication.bare_code && line =~ @publication.bare_code
          stripped = line.strip
          # Blank lines and lone continuation words are neutral: they neither
          # start a record nor break a run of ladder/CEM/bare lines.
          neutral = stripped.empty? || stripped.match?(CONTINUATION_WORD)

          starts_record =
            is_cem ||
            is_bare ||
            (is_ladder && !prev_meaningful_was_anchor)

          if starts_record
            current = +""
            records << current
          end

          current << line if current

          unless neutral
            prev_meaningful_was_anchor = !!(is_ladder || is_cem || is_bare)
          end
        end

        records
      end
    end
  end
end
