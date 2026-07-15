# frozen_string_literal: true

require_relative "patterns"
require_relative "publication"
require_relative "text"

module GovCodes
  module Dafecd
    # Parses a single specialty record (as produced by RecordSplitter) into a
    # structured header: X-form specialty, career field, CEM code (enlisted),
    # per-specialty change date, skill/qualification ladder, and the
    # (conservatively normalized) specialty title.
    #
    # Behavior is publication-specific (injected Publication); the default is the
    # enlisted directory.
    #
    # Deliberately does NOT attempt to de-glue titles that pdf-reader ran
    # together (e.g. "FORCEAVIATOR" / "SPECIALWARFARE"). Such titles are
    # title-cased verbatim and flagged via :glued_title so the deferred LLM
    # despacer can address them.
    class SpecialtyParser
      DECORATIVE = Patterns::DECORATIVE
      UNICODE_DASHES = Patterns::UNICODE_DASHES

      def initialize(record, publication: Publication.dafecd)
        @publication = publication
        @record = Text.split_glued_afsc(record, publication.glued_afsc)
        @lines = @record.lines
      end

      def parse
        codes = ladder_codes
        {
          specialty: specialty(codes),
          career_field: career_field(codes),
          cem_code: cem_code,
          bare_code: bare_code,
          changed_date: changed_date,
          name: name,
          raw_title: raw_title,
          glued_title: glued_title?
        }.merge(@publication.levels_key => levels)
      end

      private

      def ladder
        @publication.ladder
      end

      # @return [Array<String>] concrete ladder AFSCs in document order
      def ladder_codes
        @lines.filter_map { |line| line[ladder, 1] }
      end

      # The specialty key: the ladder-family X-form, or (for a bare single-code
      # record with no ladder) the literal code.
      def specialty(codes)
        return @publication.specialty_key(codes) if codes.any?
        bare = bare_code
        bare&.to_sym
      end

      def career_field(codes)
        return @publication.career_field(codes) if codes.any?
        bare = bare_code
        bare && :"#{bare[0, 2]}"
      end

      # The bare standalone code of a single-code record (officer), or nil.
      def bare_code
        return @bare_code if defined?(@bare_code)
        pattern = @publication.bare_code
        @bare_code = pattern && @record[pattern, 1]
      end

      def cem_code
        pattern = @publication.cem
        pattern && @record[pattern, 1]
      end

      def changed_date
        raw = @record[@publication.change_date, 1]
        return nil unless raw
        Text.parse_date(raw)
      end

      # @return [Hash{Integer=>Hash}] level digit => {code:, title:}
      def levels
        result = {}
        @lines.each do |line|
          next unless line =~ ladder
          code = $1
          title = normalize_level($2)
          digit = code[3].to_i
          result[digit] = {code: code, title: title}
        end
        result
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
        # deferred despacer. False positives are possible for genuinely long
        # words; the coverage report lists them for human review.
        title.split(/\s+/).any? do |token|
          bare = token.delete("()/-")
          bare.length >= 12 && bare.match?(/\A[A-Za-z]+\z/)
        end
      end

      # The title line(s) between the last ladder/bare-code line and the change
      # date / first numbered section, joined and sanitized (pre-titlecase).
      # Exposed verbatim so the de-gluer can diff against the source.
      def raw_title
        return @raw_title if defined?(@raw_title)
        @raw_title = compute_raw_title
      end

      def compute_raw_title
        last_anchor = last_anchor_index
        return nil if last_anchor.nil?

        collected = []
        @lines[(last_anchor + 1)..].each do |line|
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

      # The last line that anchors a record: a ladder line, or (for a bare
      # single-code officer record) the standalone code line.
      def last_anchor_index
        @lines.each_index.reverse_each.find do |i|
          @lines[i] =~ ladder || (@publication.bare_code && @lines[i] =~ @publication.bare_code)
        end
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
