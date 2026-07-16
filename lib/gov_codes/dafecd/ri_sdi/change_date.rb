# frozen_string_literal: true

require_relative "../text"

module GovCodes
  module Dafecd
    module RiSdi
      # Extracts the per-record change/effective date from an RI or SDI record's
      # header region.
      #
      # The RI/SDI sections of the DAFECD/DAFOCD use noticeably messier date
      # annotations than the AFSC ladder records the existing
      # Publication#change_date patterns handle. Rather than loosen those shared
      # patterns (which would risk perturbing the already-shipped enlisted/officer
      # artifacts), this module owns a deliberately tolerant capture regex used
      # only on the new content:
      #
      #   * a leading extra word before the date
      #       "(Change Effective 31 Oct 18)", "(Established Effective 31 Oct 22)"
      #   * a long leading clause ending in a lowercase "effective"
      #       "(Change to description only effective 11 May 15)"
      #   * a glued day/month  "(Established 30Apr 25)"
      #   * a dual date; the FIRST is captured (matching the officer convention)
      #       "(Changed 31 Oct 16, Effective 8 Feb 16)"  -> 2016-10-31
      #   * a missing/misplaced open paren (pdf glue)
      #       "Established 31 Oct 25   )"
      #
      # The captured substring is normalized to ISO 8601 by the shared
      # Text.parse_date (which already tolerates the glued day/month). Returns nil
      # when the given text carries no such annotation.
      module ChangeDate
        # A directory date: "31 Oct 25", "5 June 2013", the glued "30Apr 25", or
        # the fully glued "30Apr20" (officer 81D0). The gap before BOTH the month
        # and the year is optional to absorb pdf-reader's glue.
        DATE = /\d{1,2}\s*[A-Za-z]{3,9}\s*\d{2,4}/

        # A change-date annotation: a capitalized change keyword, then a lazy run
        # of same-annotation filler (no newline, no close paren), then the first
        # date. The lazy filler is what captures the FIRST date of a dual-date
        # line and absorbs the "Effective"/"effective"/"to description only"
        # bridging words.
        ANNOTATION = /(?:Changed|Established|Effective|Change)\b[^)\n]*?(#{DATE})/

        module_function

        # @param text [String] the record's header region (or any text slice)
        # @return [String, nil] the ISO 8601 change date, or nil when absent
        def extract(text)
          raw = text.to_s[ANNOTATION, 1]
          raw && normalize(raw)
        end

        # Normalize an already-isolated raw date ("31 Oct 24", "30Apr20") to ISO
        # 8601. Re-spaces any letter/digit glue so the shared date normalizer,
        # which needs a gap before the year, can read it. Returns nil when the raw
        # is not a date.
        def normalize(raw)
          Text.parse_date(raw.to_s.gsub(/([A-Za-z])(?=\d)/, '\1 ').gsub(/(\d)(?=[A-Za-z])/, '\1 '))
        end
      end
    end
  end
end
