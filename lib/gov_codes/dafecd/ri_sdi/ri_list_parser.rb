# frozen_string_literal: true

require_relative "../patterns"
require_relative "../shredout_parser"
require_relative "config"
require_relative "change_date"
require_relative "title"

module GovCodes
  module Dafecd
    module RiSdi
      # Parses a flat, numbered Reporting Identifiers (RI) list into per-code
      # entries.
      #
      # Each top-level list item ("<n>. <code>, <title>. <date>") is one record,
      # delimited by the next top-level number. The anchor tolerates the source's
      # pdf-reader glue and decoration: an optional run of spaces (or none) after
      # "<n>.", an optional leading decorative star, a comma OR a bare space
      # before the title, and a list number glued to the code ("34.9T000").
      #
      # The title runs from the code to the FIRST of a change-date parenthetical
      # or a sentence-ending period, and may wrap across physical lines. The
      # officer directory omits the comma and always ends the title at the first
      # period ("90G0 General Officer. Use this identifier ...").
      #
      # Rich records carry sub-paragraphs, sometimes including a
      # "<n>.x Specialty Shredouts:" table, which is parsed by the reused
      # ShredoutParser. Records are returned in document order; #entries also
      # carries each item's :number so callers can run the 1..N completeness check.
      class RiListParser
        DECORATIVE = Patterns::DECORATIVE

        # A sub-paragraph line ("24.1.", "56.2.1.") — where a record's body begins.
        # Distinct from the anchor line, whose "<n>." is immediately followed by a
        # code (letter in the second position), not another number-and-dot.
        SUBPARAGRAPH = /\A\s*\d+\.\d/

        # The title's trailing change-date parenthetical.
        DATE_PAREN = /\((?:Changed|Established|Effective|Change)\b/

        # A sentence-ending period: a "." followed by whitespace or end of string.
        SENTENCE_PERIOD = /\.(?=\s|\z)/

        def initialize(text, config: Config.dafecd)
          @config = config
          @lines = text.lines.reject { |line| line =~ config.header }
        end

        # @return [Array<Hash>] one entry per RI code, in document order
        def entries
          records.filter_map { |record| parse(record) }
        end

        private

        # Split the section into records at each top-level anchor line.
        def records
          records = []
          current = nil
          @lines.each do |line|
            if line.match?(@config.ri_anchor)
              current = +""
              records << current
            end
            current << line if current
          end
          records
        end

        def parse(record)
          lines = record.lines
          m = lines.first.match(@config.ri_anchor)
          return nil unless m

          number = m[1].to_i
          code = m[2]
          region = title_region(m[3], lines.drop(1))

          raw_title = extract_title(region)
          name = raw_title && Title.titleize(raw_title)

          {
            number: number,
            code: code,
            name: name,
            raw_title: raw_title,
            changed_date: ChangeDate.extract(region),
            glued_title: Title.glued?(name),
            shredouts: shredouts(record)
          }
        end

        # The joined header region: the anchor line's title remainder plus every
        # continuation line up to the first sub-paragraph, sanitized and with page
        # numbers dropped. This holds the title and its trailing date.
        def title_region(anchor_rest, rest_lines)
          parts = [Title.sanitize(anchor_rest)]
          rest_lines.each do |line|
            break if line.match?(SUBPARAGRAPH)
            stripped = Title.sanitize(line)
            next if stripped.empty?
            next if stripped.match?(/\A\d+\z/) # bare page number
            parts << stripped
          end
          parts.reject(&:empty?).join(" ")
        end

        # The title: the region up to the first date parenthetical or sentence
        # period, whichever comes first; the whole region when neither is present
        # (e.g. "DAFWorld Class Athlete Program (WCAP)").
        def extract_title(region)
          cut = [region =~ DATE_PAREN, region =~ SENTENCE_PERIOD].compact.min
          title = (cut ? region[0...cut] : region).sub(/[\s.,]+\z/, "").strip
          title.empty? ? nil : title
        end

        def shredouts(record)
          ShredoutParser.new(
            record, publication: @config, pair: ShredoutParser::RI_SDI_PAIR
          ).parse
        end
      end
    end
  end
end
