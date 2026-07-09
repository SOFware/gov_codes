# frozen_string_literal: true

require_relative "patterns"
require_relative "text"

module GovCodes
  module Dafecd
    # Parses a single DAFECD specialty record (as produced by RecordSplitter)
    # into a structured header: X-form specialty, career field, CEM code,
    # per-specialty change date, skill ladder, and the (conservatively
    # normalized) specialty title.
    #
    # Deliberately does NOT attempt to de-glue titles that pdf-reader ran
    # together (e.g. "FORCEAVIATOR"). Such titles are title-cased verbatim and
    # flagged via :glued_title so the deferred C.2 LLM despacer can address them.
    class SpecialtyParser
      # Ladder line (captures concrete AFSC as group 1, skill-level word as
      # group 2) and CEM line, shared with RecordSplitter via Patterns.
      LADDER = Patterns::LADDER
      CEM = Patterns::CEM

      CHANGE_DATE = /\((?:Changed|Established|Effective)\s+(\d{1,2}\s+\w{3,9}\s+\d{2,4})\)/

      DECORATIVE = Patterns::DECORATIVE
      UNICODE_DASHES = Patterns::UNICODE_DASHES

      def initialize(record)
        @record = Text.split_glued_afsc(record)
        @lines = @record.lines
      end

      def parse
        codes = ladder_codes
        {
          specialty: x_form(codes),
          career_field: career_field(codes),
          cem_code: cem_code,
          changed_date: changed_date,
          skill_levels: skill_levels,
          name: name,
          raw_title: raw_title,
          glued_title: glued_title?
        }
      end

      private

      # @return [Array<String>] concrete ladder AFSCs in document order
      def ladder_codes
        @lines.filter_map { |line| line[LADDER, 1] }
      end

      def x_form(codes)
        basis = specialty_basis(codes)
        return nil if basis.empty?
        :"#{basis.first[0, 3]}X#{most_common_specific(basis)}"
      end

      def career_field(codes)
        basis = specialty_basis(codes)
        return nil if basis.empty?
        :"#{basis.first[0, 2]}"
      end

      # The ladder codes that define the specialty. A subdivision superintendent
      # often carries specific digit 0 (e.g. 4J090 atop the 4J0X2 ladder), so the
      # specialty is defined by its non-superintendent (skill digit != 9) levels;
      # fall back to all codes when only a superintendent is present.
      def specialty_basis(codes)
        non_super = codes.reject { |code| code[3] == "9" }
        non_super.empty? ? codes : non_super
      end

      # The most frequent specific (5th) digit among the basis codes.
      def most_common_specific(basis)
        basis.map { |code| code[4] }.group_by(&:itself).max_by { |_, v| v.size }.first
      end

      def cem_code
        @record[CEM, 1]
      end

      def changed_date
        raw = @record[CHANGE_DATE, 1]
        return nil unless raw
        Text.parse_date(raw)
      end

      # @return [Hash{Integer=>Hash}] skill-level digit => {code:, title:}
      def skill_levels
        levels = {}
        @lines.each do |line|
          next unless line =~ LADDER
          code = $1
          title = normalize_level($2)
          digit = code[3].to_i
          levels[digit] = {code: code, title: title}
        end
        levels
      end

      def normalize_level(word)
        collapsed = word.gsub(/\s+/, " ").strip
        (collapsed == "Senior Enlisted") ? "Senior Enlisted Leader" : collapsed
      end

      def name
        raw = raw_title
        return nil if raw.nil? || raw.empty?
        titleize(raw)
      end

      def glued_title?
        title = name
        return false if title.nil?
        # Heuristic proxy for pdf-reader glue: an unusually long single token
        # (excluding preserved acronyms). Reported, not relied upon, for the
        # deferred C.2 despacer. False positives are possible for genuinely
        # long words; the coverage report lists them for human review.
        title.split(/\s+/).any? do |token|
          bare = token.delete("()/-")
          bare.length >= 12 && bare.match?(/\A[A-Za-z]+\z/)
        end
      end

      # The title line(s) between the last ladder line and the change date /
      # first numbered section, joined and sanitized (pre-titlecase). Accepts
      # both the common ALL-CAPS titles and the Title-Case titles used by a few
      # special-duty specialties (e.g. "Multi-domain Operations Aviator").
      # Exposed verbatim so the C.2 de-gluer can diff against the source.
      def raw_title
        return @raw_title if defined?(@raw_title)
        @raw_title = compute_raw_title
      end

      def compute_raw_title
        last_ladder = last_ladder_index
        return nil if last_ladder.nil?

        collected = []
        @lines[(last_ladder + 1)..].each do |line|
          stripped = sanitize(line)
          next if stripped.empty?
          next if stripped.match?(/\A\d+\z/)          # bare page number
          next if stripped.match?(/\A[A-Z][a-z]+\z/)  # wrapped ladder word (e.g. "Leader")
          break if stripped.match?(/\A\(?(?:Changed|Established|Effective)\b/) # change date
          break if stripped.match?(/\A\d+\./)          # numbered section (1. / 1.Specialty / 3.4.1)
          break if stripped.match?(/\b(?:Specialty Summary|Special Duty Summary|Duties and Responsibilities)\b/)

          if title_line?(stripped)
            collected << stripped
          else
            break
          end
        end

        return nil if collected.empty?
        collected.join(" ")
      end

      def last_ladder_index
        @lines.each_index.reverse_each.find { |i| @lines[i] =~ LADDER }
      end

      # Remove decorative symbol glyphs, normalize unicode dashes, and collapse
      # runs of whitespace (pdf-reader pads some titles with long space runs) so
      # a title line reduces to its plain-text content.
      def sanitize(line)
        line.gsub(DECORATIVE, "").gsub(UNICODE_DASHES, "-").gsub(/\s+/, " ").strip
      end

      # A title line is short, starts with a capital / paren / digit, and is not
      # a prose sentence. Accepts ALL-CAPS and Title-Case forms; the boundary
      # breaks in compute_raw_title stop collection before the summary prose.
      def title_line?(stripped)
        return false if stripped.length > 70
        return false unless stripped.match?(/\A[A-Z0-9(]/)
        return false if stripped.split(/\s+/).size > 10
        return false if stripped.match?(/[a-z]\.\s+[A-Z]/) # mid-line sentence break = prose
        stripped.match?(/[A-Za-z]/)
      end

      def titleize(raw)
        raw.split(/\s+/).map { |word| titleize_word(word) }.join(" ")
      end

      def titleize_word(word)
        # Preserve parenthesized acronyms, e.g. "(RPA)", "(ISR)", "(C2)".
        return word if word.match?(/\A\([A-Z0-9&\/.-]{2,}\)\z/)
        # Preserve all-caps tokens containing a digit, e.g. "C2", "F16".
        return word if word.match?(/\A[A-Z]*\d[A-Z0-9]*\z/) && word.match?(/[A-Z0-9]/)

        word.split(/([\/-])/).map { |seg|
          seg.match?(/[A-Za-z]/) ? seg.capitalize : seg
        }.join
      end
    end
  end
end
