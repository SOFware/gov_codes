# frozen_string_literal: true

require_relative "config"
require_relative "title"

module GovCodes
  module Dafecd
    module RiSdi
      # Splits a Special Duty Identifiers (SDI) section into one string per record.
      #
      # A record begins at either:
      #   * a run of "SDI <code>" card anchors (the first anchor of the run), or
      #   * a "CEM Code <code>" line — the single ladder record (Premier Honor
      #     Guard, 8G000) embedded in the enlisted AF SDI section. It is split out
      #     as its own record so its body (notably its shredout table) can never
      #     bleed into the preceding card; the AFSC pipeline parses it downstream.
      #
      # Running page headers are stripped first. Consecutive card anchors stay in
      # one record (the multi-code Air Advisor blocks). A wrapped-prose false
      # positive ("SDI 8P000, completion of a current T5 ...") does NOT start a
      # record — its inline "title" fails the real-title test, so it is left as
      # body of the surrounding record and later rejected by SdiCardParser.
      class SdiSectionSplitter
        def initialize(text, config: Config.dafecd)
          @config = config
          @lines = text.lines.reject { |line| line =~ config.header }
        end

        # @return [Array<String>] one string per record
        def records
          records = []
          current = nil
          prev_meaningful_was_anchor = false

          @lines.each do |line|
            is_card = card_anchor?(line)
            is_cem = line.match?(@config.cem)
            stripped = line.strip
            neutral = stripped.empty? || stripped.match?(/\A\d+\z/)

            starts_record = is_cem || (is_card && !prev_meaningful_was_anchor)

            if starts_record
              current = +""
              records << current
            end

            current << line if current

            unless neutral
              # A CEM line's ladder ("AFSC 8G091 ...") keeps the run open so the
              # card detector does not re-trigger inside the ladder record.
              prev_meaningful_was_anchor = is_card || is_cem || ladder_line?(line)
            end
          end

          records
        end

        private

        # A card anchor: a standalone "SDI <code>" line, or an inline-title anchor
        # whose title is a real title (rejecting the wrapped-prose false positive).
        def card_anchor?(line)
          return true if line.match?(@config.sdi_anchor)
          m = line.match(@config.sdi_inline_anchor)
          m && Title.real?(Title.sanitize(m[2]))
        end

        # A ladder line inside the embedded CEM record, e.g. "AFSC 8G091 ...".
        def ladder_line?(line)
          line.match?(/^\s*AFSC\s+\d[A-Z]\d\d\d/)
        end
      end
    end
  end
end
