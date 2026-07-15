# frozen_string_literal: true

require_relative "patterns"
require_relative "publication"

module GovCodes
  module Dafecd
    # Parses a "Specialty Shredouts" table into a suffix => name map.
    #
    # The table is laid out in two side-by-side columns, e.g. (enlisted):
    #
    #     Suffix     Primary Aircraft            Suffix    Primary Aircraft
    #        A       C-5 Flight Engineer            L      C-130H Flight Engineer
    #        B       C-5 Loadmaster                 N      C-130H Loadmaster
    #
    # The officer directory uses the same two-column interleave under a different
    # heading ("Suffix ... Portion of AFS to Which Related"). Both columns are
    # captured. Values that wrap onto a continuation line are captured only up to
    # the wrap (a documented, minor limitation). The table header is
    # publication-specific (injected Publication); the default is enlisted.
    class ShredoutParser
      # A single suffix/name cell. The suffix is one capital letter followed by
      # 2+ spaces; the name runs until 2+ spaces precede the next column's suffix
      # or the line ends.
      PAIR = /\b([A-Z])\s{2,}([A-Z0-9][A-Za-z0-9 \/().-]{2,45}?)(?=\s{2,}[A-Z]\s{2,}|\s*$)/

      def initialize(text, publication: Publication.dafecd)
        @text = text
        @header = publication.shredout_header
      end

      # @return [Hash{Symbol=>String}] suffix letter => shredout name
      def parse
        result = {}
        table_lines.each do |line|
          # Strip stray decorative glyphs that would otherwise break the column
          # lookahead (e.g. a U+F0EA bullet sitting in a between-column gap).
          line.gsub(Patterns::DECORATIVE, " ").scan(PAIR) do |suffix, name|
            result[suffix.to_sym] = name.strip
          end
        end
        result
      end

      private

      # Lines belonging to the shredout table body: everything after the
      # "Suffix ..." header up to a terminating boundary (a *NOTE, a numbered
      # section, or the end of the given text).
      def table_lines
        lines = @text.lines
        start = lines.index { |line| line.match?(@header) }
        return [] if start.nil?

        body = []
        lines[(start + 1)..].each do |line|
          stripped = line.strip
          break if stripped.start_with?("*NOTE", "NOTE:")
          break if stripped.match?(/\A\d+(?:\.\d+)*\.\s/)
          body << line
        end
        body
      end
    end
  end
end
