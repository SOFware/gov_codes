# frozen_string_literal: true

require_relative "../patterns"

module GovCodes
  module Dafecd
    module RiSdi
      # Conservative title normalization for RI/SDI records.
      #
      # These helpers mirror the AFSC SpecialtyParser's title handling exactly
      # (sanitize -> title-case verbatim, flag probable pdf glue) but live in
      # their own module so the RI/SDI extraction shares NONE of the AFSC ladder
      # pipeline's mutable state — the already-shipped enlisted/officer artifacts
      # cannot be perturbed by anything done here.
      #
      # As in the AFSC pipeline, no de-gluing is attempted: a run-together title
      # like "ENLISTEDAIDE" becomes "Enlistedaide" and is flagged via #glued? for
      # the deferred, governed de-glue pass. Clean titles are authored out of band.
      module Title
        DECORATIVE = Patterns::DECORATIVE
        UNICODE_DASHES = Patterns::UNICODE_DASHES

        module_function

        # Remove decorative symbol glyphs, normalize unicode dashes, and collapse
        # whitespace runs so a title line reduces to its plain-text content.
        def sanitize(line)
          line.gsub(DECORATIVE, "").gsub(UNICODE_DASHES, "-").gsub(/\s+/, " ").strip
        end

        # A title line is short, starts with a capital / paren / digit, and is not
        # a prose sentence. Accepts ALL-CAPS and Title-Case forms.
        def title_line?(stripped)
          return false if stripped.length > 90
          return false unless stripped.match?(/\A[A-Z0-9(]/)
          return false if stripped.split(/\s+/).size > 12
          return false if stripped.match?(/[a-z]\.\s+[A-Z]/) # mid-line sentence break = prose
          stripped.match?(/[A-Za-z]/)
        end

        # Conservative title-case: capitalize each alphabetic word, preserving
        # parenthesized acronyms and all-caps-with-digit tokens.
        def titleize(raw)
          raw.split(/\s+/).map { |word| titleize_word(word) }.join(" ")
        end

        def titleize_word(word)
          return word if word.match?(/\A\([A-Z0-9&\/.-]{2,}\)\z/)
          return word if word.match?(/\A[A-Z]*\d[A-Z0-9]*\z/) && word.match?(/[A-Z0-9]/)

          word.split(/([\/-])/).map { |seg|
            seg.match?(/[A-Za-z]/) ? seg.capitalize : seg
          }.join
        end

        # A real title starts with a capital letter, a digit, or an opening paren
        # — never the lowercase word that begins a wrapped prose sentence (the
        # "SDI 8P000, completion of ..." false positive).
        def real?(title)
          t = title.to_s.strip
          !t.empty? && t.match?(/\A[A-Z0-9(]/)
        end

        # Heuristic proxy for pdf-reader glue: an unusually long single token
        # (excluding preserved acronyms). Reported, not relied upon.
        def glued?(name)
          return false if name.nil?
          name.split(/\s+/).any? do |token|
            bare = token.delete("()/-")
            bare.length >= 12 && bare.match?(/\A[A-Za-z]+\z/)
          end
        end
      end
    end
  end
end
