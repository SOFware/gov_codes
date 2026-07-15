# frozen_string_literal: true

module GovCodes
  module Dafecd
    # Extracts shredout-level acronyms for the officer directory from two
    # deterministic sources (both grounded verbatim in the record source):
    #
    #   a. Shredout TABLE values whose meaning ends in a trailing "(ACR)", e.g.
    #      "Air Liaison Officer (ALO)" -> {U: "ALO"}. The :shredouts value is kept
    #      verbatim; only the acronym is lifted out.
    #
    #   b. A numbered in-record enumeration of the form
    #      "<family>X<shred> (<Title> (<ACR>))", e.g. in the 19Z record:
    #      "19ZXB (Tactical Air Control Party Officer (TACPO))" -> {B: "TACPO"}.
    #      Only codes belonging to the record's own specialty family are accepted.
    module ShredoutAcronyms
      # A shredout value's trailing parenthetical acronym.
      TABLE_ACRONYM = /\(([A-Z][A-Z0-9]{1,7})\)\s*\z/

      module_function

      # @param shredouts [Hash{Symbol=>String}] parsed suffix => meaning
      # @return [Hash{Symbol=>String}] suffix => trailing acronym
      def from_table(shredouts)
        result = {}
        shredouts.each do |suffix, meaning|
          match = meaning.match(TABLE_ACRONYM)
          result[suffix] = match[1] if match
        end
        result
      end

      # @param record [String] the specialty record's source text
      # @param family [String] the record's 3-char specialty family (e.g. "19Z")
      # @return [Hash{Symbol=>String}] shred letter => acronym
      def from_enumeration(record, family)
        return {} if family.nil? || family.empty?
        result = {}
        pattern = /#{Regexp.escape(family)}X([A-Z])\s*\([^()]*\(([A-Z][A-Z0-9]{1,7})\)\)/
        record.scan(pattern) do |shred, acronym|
          result[shred.to_sym] = acronym
        end
        result
      end
    end
  end
end
