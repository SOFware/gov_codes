# frozen_string_literal: true

module GovCodes
  module Dafecd
    # Shared text utilities for the DAFECD extractor: normalization of
    # pdf-reader glue artifacts and date parsing. Used by RecordSplitter,
    # SpecialtyParser, and the extractor CLI so the behavior stays consistent.
    module Text
      MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec]
        .each_with_index.to_h { |m, i| [m, i + 1] }.freeze

      # Default (enlisted) glue boundary: a letter immediately followed by an
      # "AFSC <5-char enlisted code>".
      DEFAULT_GLUED_AFSC = /(?<=[A-Za-z])(?=AFSC \d[A-Z]\d\d\d)/

      module_function

      # pdf-reader frequently glues the word "AFSC" to a preceding word when a
      # ladder line wraps, e.g. "LeaderAFSC 1A178*, Craftsman". Insert a newline
      # before an "AFSC <code>" that is glued to a letter so the ladder line is
      # detectable at line start. This is safe for prose mentions such as
      # "possession ofAFSC 1A132" because ladder detection additionally requires
      # a skill-level word at end of line, which prose lines do not satisfy.
      #
      # The glue boundary is publication-specific (the enlisted and officer AFSC
      # code shapes differ); pass the publication's pattern to override the
      # enlisted default.
      def split_glued_afsc(text, pattern = DEFAULT_GLUED_AFSC)
        text.gsub(pattern, "\n")
      end

      # Normalize a directory date such as "31 Oct 25", "31 Oct 2024", or the
      # officer directory's glued "30Apr 25" to ISO 8601 ("2025-10-31" /
      # "2024-10-31"). The day/month gap is optional (\s*) to absorb pdf-reader's
      # glued day/month; the enlisted (always-spaced) dates are unaffected.
      # Returns nil when unparseable.
      def parse_date(raw)
        return nil unless raw =~ /(\d{1,2})\s*(\w{3,9})\s+(\d{2,4})/
        day = $1.to_i
        month = MONTHS[$2[0, 3].downcase]
        year = $3.to_i
        year += 2000 if year < 100
        return nil unless month
        format("%04d-%02d-%02d", year, month, day)
      end
    end
  end
end
