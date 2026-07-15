# frozen_string_literal: true

require_relative "patterns"
require_relative "text"

module GovCodes
  # Dev-only tooling that parses the official Department of the Air Force
  # Enlisted Classification Directory (DAFECD) PDF text into structured data.
  #
  # These classes are NEVER required by the gem runtime. They are used offline
  # (via bin/extract_afsc_from_pdf.rb) to regenerate the versioned index when a
  # new directory is released.
  module Dafecd
    # Splits the full DAFECD text into one string per specialty record.
    #
    # A specialty record begins at either:
    #   * a "CEM Code <code>" line, or
    #   * the first ladder line ("AFSC <code>, <skill title>") of a ladder group
    #     that is NOT immediately preceded (ignoring blank lines) by another
    #     ladder line or a CEM Code line.
    #
    # Running page headers ("DAFECD, <date>") and the page-number lines that
    # accompany them are stripped before splitting.
    class RecordSplitter
      # Running header emitted on every page, e.g. "DAFECD, 31 Oct 25".
      HEADER = /^\s*DAFECD,\s+\d/

      LADDER = Patterns::LADDER
      CEM = Patterns::CEM

      # A lone title-case word on its own line (e.g. "Leader" left behind when
      # Text.split_glued_afsc splits "LeaderAFSC 1A178"). Such wrapped
      # continuations must not break a ladder group.
      CONTINUATION_WORD = /\A[A-Z][a-z]+\z/

      def initialize(text)
        @text = Text.split_glued_afsc(text)
      end

      # @return [Array<String>] one string per specialty record
      def records
        lines = @text.lines.reject { |line| line =~ HEADER }

        records = []
        current = nil
        prev_meaningful_was_ladder_or_cem = false

        lines.each do |line|
          is_ladder = line =~ LADDER
          is_cem = line =~ CEM
          stripped = line.strip
          # Blank lines and lone continuation words are neutral: they neither
          # start a record nor break a run of ladder/CEM lines.
          neutral = stripped.empty? || stripped.match?(CONTINUATION_WORD)

          starts_record =
            is_cem ||
            (is_ladder && !prev_meaningful_was_ladder_or_cem)

          if starts_record
            current = +""
            records << current
          end

          current << line if current

          unless neutral
            prev_meaningful_was_ladder_or_cem = is_ladder || is_cem
          end
        end

        records
      end
    end
  end
end
