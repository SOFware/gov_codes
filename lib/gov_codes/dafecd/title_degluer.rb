# frozen_string_literal: true

require "yaml"

module GovCodes
  module Dafecd
    # Applies verified de-glued specialty titles.
    #
    # pdf-reader drops spaces inside DAFECD titles ("MOBILITY FORCEAVIATOR").
    # The deterministic extractor title-cases those verbatim ("Mobility
    # Forceaviator") and cannot safely re-insert the missing spaces. The clean
    # titles are produced out of band and shipped in title_overrides.yml.
    #
    # The de-gluing invariant — enforced at build time by IndexBuilder — is that
    # an override may only change SPACING and CASE relative to the raw source
    # title; no letter, digit, or punctuation may change. Any drift (e.g. a
    # future release renamed the specialty) fails the build loudly rather than
    # silently applying a stale title.
    class TitleDegluer
      DEFAULT_PATH = File.expand_path("title_overrides.yml", __dir__)

      # @return [TitleDegluer] loaded from the shipped overrides file
      def self.load(path = DEFAULT_PATH)
        overrides = YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
        new(overrides)
      end

      # @return [TitleDegluer] loaded from +publication+'s overrides file, or an
      #   empty de-gluer when that file does not yet exist (officer titles are
      #   supplied out of band in a later phase).
      def self.for(publication)
        path = publication.title_overrides_path
        File.exist?(path) ? load(path) : empty
      end

      # An empty de-gluer applies no overrides (keeps the auto-titlecased names).
      def self.empty
        new({})
      end

      # Whitespace-and-case-insensitive normalization used for the invariant.
      def self.norm(str)
        str.to_s.gsub(/\s+/, "").downcase
      end

      # Does +override+ differ from +raw_title+ only in spacing/case?
      def self.matches_source?(override, raw_title)
        return false if raw_title.nil?
        norm(override) == norm(raw_title)
      end

      # @param overrides [Hash{Symbol=>String}] specialty => clean title
      def initialize(overrides = {})
        @overrides = overrides
      end

      # @return [String, nil] the clean title for +specialty+, or nil
      def override_for(specialty)
        @overrides[specialty]
      end

      def any?
        !@overrides.empty?
      end
    end
  end
end
