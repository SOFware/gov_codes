# frozen_string_literal: true

require_relative "../patterns"
require_relative "../shredout_parser"
require_relative "config"
require_relative "change_date"
require_relative "title"

module GovCodes
  module Dafecd
    module RiSdi
      # Parses ONE "SDI card" record block into per-code entries.
      #
      # A card block is a run of one or more "SDI <code>" anchor lines followed by
      # a shared body: a title (on its own line, or inline after the code), a
      # change-date annotation, numbered sections, and (occasionally) a
      # "Specialty Shredouts" table. Enlisted codes are 5 chars ("8A200"); officer
      # codes are 4 ("80C0"); the shape is supplied by the injected Config.
      #
      # A multi-code block (e.g. the Air Advisor codes 8L100/8L200/8L300, each
      # with its own inline title but one shared body) yields one entry per code.
      #
      # A wrapped-prose false positive — an "SDI <code>," anchor whose inline
      # "title" is actually the lowercase continuation of a sentence, e.g.
      # "SDI 8P000, completion of a current T5 Investigation ..." — is rejected:
      # its title fails the real-title test, leaving the block with no valid
      # anchor, so #entries returns [].
      class SdiCardParser
        DECORATIVE = Patterns::DECORATIVE

        Anchor = Struct.new(:code, :inline_title, keyword_init: true)

        # A bare (keyword-less) date parenthetical, e.g. "(31 Oct 24)" — the date
        # annotation on the officer 88X0 card carries no Changed/Established word.
        BARE_DATE = /\(\s*(\d{1,2}\s*[A-Za-z]{3,9}\s*\d{2,4})\s*\)/
        BARE_DATE_LINE = /\A#{BARE_DATE}/

        # A keyword date annotation ("(Changed ...)"), open paren optional.
        KEYWORD_DATE_LINE = /\A\(?\s*(?:Changed|Established|Effective|Change)\b/

        def initialize(record, config: Config.dafecd)
          @config = config
          @lines = record.lines.reject { |line| line =~ config.header }
        end

        # @return [Array<Hash>] one entry hash per code in the block
        def entries
          anchors = self.anchors
          return [] if anchors.empty?

          shared = shared_title
          date = changed_date
          shreds = shredouts

          anchors.map do |anchor|
            raw = anchor.inline_title || shared
            name = raw && Title.titleize(raw)
            {
              code: anchor.code,
              name: name,
              raw_title: raw,
              changed_date: date,
              glued_title: Title.glued?(name),
              shredouts: shreds
            }
          end
        end

        private

        # The valid SDI anchors in document order. An inline-title anchor whose
        # title is not a real title is treated as a non-anchor (the false-positive
        # rejection); a standalone "SDI <code>" line is always a valid anchor.
        def anchors
          @lines.filter_map do |line|
            if (m = line.match(@config.sdi_anchor))
              Anchor.new(code: m[1], inline_title: nil)
            elsif (m = line.match(@config.sdi_inline_anchor))
              title = Title.sanitize(m[2])
              Title.real?(title) ? Anchor.new(code: m[1], inline_title: title) : nil
            end
          end
        end

        # Index of the last VALID anchor line, or nil. A false-positive inline
        # anchor in the body ("SDI 8P000, completion of ...") must not be treated
        # as an anchor here, or the standalone card's title lookup would start
        # after it and find nothing.
        def last_anchor_index
          @lines.each_index.reverse_each.find { |i| valid_anchor?(@lines[i]) }
        end

        def valid_anchor?(line)
          return true if line.match?(@config.sdi_anchor)
          m = line.match(@config.sdi_inline_anchor)
          m && Title.real?(Title.sanitize(m[2]))
        end

        # The standalone title: title lines between the last anchor and the date /
        # first numbered section, joined and sanitized. nil when the block carries
        # only inline titles (or no title line).
        def shared_title
          last = last_anchor_index
          return nil if last.nil?

          collected = []
          @lines[(last + 1)..].each do |line|
            stripped = Title.sanitize(line)
            next if stripped.empty?
            next if stripped.match?(/\A\d+\z/)          # bare page number
            break if date_line?(stripped)
            break if stripped.match?(/\A\d+\./)         # numbered section
            break unless Title.title_line?(stripped)
            collected << stripped
          end
          collected.empty? ? nil : collected.join(" ")
        end

        # Everything up to the first numbered section, where the change date lives.
        def head_region
          cut = @lines.index { |line| line.match?(/\A\s*\d+\.\s/) }
          (cut ? @lines[0...cut] : @lines).join
        end

        # The change date: a keyword annotation, or (officer 88X0) a keyword-less
        # bare date parenthetical in the card's header region.
        def changed_date
          region = head_region
          ChangeDate.extract(region) || bare_date(region)
        end

        def bare_date(region)
          m = region.match(BARE_DATE)
          m && ChangeDate.normalize(m[1])
        end

        def shredouts
          ShredoutParser.new(
            @lines.join, publication: @config, pair: ShredoutParser::RI_SDI_PAIR
          ).parse
        end

        # A line that ends title collection: a keyword date annotation OR a bare
        # date parenthetical ("(31 Oct 24)").
        def date_line?(stripped)
          stripped.match?(KEYWORD_DATE_LINE) || stripped.match?(BARE_DATE_LINE)
        end
      end
    end
  end
end
