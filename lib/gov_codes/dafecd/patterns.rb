# frozen_string_literal: true

module GovCodes
  module Dafecd
    # Shared line-anchor patterns used by both RecordSplitter (to detect record
    # boundaries) and SpecialtyParser (to extract the ladder). Kept in one place
    # so the two never drift apart.
    module Patterns
      # Skill-ladder line. Captures the concrete 5-char AFSC (group 1) and the
      # skill-level word (group 2). Tolerant of the DAFECD's formatting quirks:
      #   * an OPTIONAL leading "AFSC" prefix — pdf-reader sometimes shifts the
      #     "AFSC" token to the end of the previous line, leaving a bare code at
      #     line start (e.g. "1A194, SuperintendentAFSC"),
      #   * an optional TRAILING "AFSC" (that shifted token),
      #   * an optional "*" restriction marker on the code,
      #   * an optional alternate code, e.g. "3E471 or 3E471A",
      #   * an optional comma,
      #   * an optional specialty-specific qualifier before the level word,
      #     e.g. "Cryptologic Intelligence Superintendent",
      #   * a wrapped "Senior Enlisted" (Leader on the following line),
      #   * an optional trailing acronym, e.g. "Senior Enlisted Leader (SEL)".
      # The code must be at line start and the level word must END the line;
      # together these reject prose mentions such as "possession ofAFSC 1Z331,
      # which ...". (Prefix-glue like "LeaderAFSC 1A178" is split onto its own
      # line by Text.split_glued_afsc before this pattern is applied.)
      LADDER = /
        ^\s*(?:AFSC\s+)?(\d[A-Z]\d\d\d)\*?
        (?:\s+or\s+\d[A-Z0-9]+)?
        ,?\s*
        (?:[A-Za-z][A-Za-z\/]*\s+){0,3}
        (Helper|Apprentice|Journeyman|Craftsman|
         Superintendent|Senior\s+Enlisted(?:\s+Leader)?|Entry)
        (?:\s*\([A-Z]{2,6}\))?
        (?:\s*AFSC)?
        \s*$
      /x

      # CEM (Chief Enlisted Manager) code line, e.g. "CEM Code 1A100*".
      CEM = /^\s*CEM Code\s+(\d[A-Z]\d00)\*?/

      # Decorative glyphs pdf-reader lifts from symbol fonts and scatters through
      # the text: Private Use Area bullets, black/white stars, and common
      # bullets. They are never part of the data and are stripped before parsing.
      DECORATIVE = /[\u{E000}-\u{F8FF}★☆•●▪■⁃∙]/

      # Unicode dashes the directory uses, normalized to ASCII "-".
      UNICODE_DASHES = /[‐-―−]/
    end
  end
end
