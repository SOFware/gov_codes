# frozen_string_literal: true

require "yaml"

module GovCodes
  module Dafecd
    # Applies verified de-glued shredout values.
    #
    # pdf-reader drops spaces inside shredout meanings exactly as it does inside
    # specialty titles ("ImageryAnalyst", "TacticalAir Control Party Officer").
    # The deterministic extractor keeps those verbatim and cannot safely re-insert
    # the missing spaces. The clean values are produced out of band and shipped in
    # per-publication files under shredout_overrides/ (mirroring title_overrides/).
    #
    # The data is nested one level deeper than the title overrides: a specialty
    # maps to a suffix => clean-value map, e.g.
    #
    #   :1A1X8:
    #     :A: C-32/C-40B/C Flight Attendant
    #     :C: C-37A/B Flight Attendant
    #
    # The de-gluing invariant — enforced at build time by IndexBuilder — is that
    # an override may only change SPACING and CASE relative to the raw extracted
    # value; no letter, digit, or punctuation may change. Any drift (or an
    # override targeting a shredout absent from the source) fails the build loudly
    # rather than silently applying a stale value.
    class ShredoutDegluer
      # @return [ShredoutDegluer] loaded from +path+
      def self.load(path)
        overrides = YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
        new(overrides)
      end

      # @return [ShredoutDegluer] loaded from +publication+'s overrides file, or
      #   an empty de-gluer when that file does not exist.
      def self.for(publication)
        path = publication.shredout_overrides_path
        File.exist?(path) ? load(path) : empty
      end

      # An empty de-gluer applies no overrides (keeps the verbatim values).
      def self.empty
        new({})
      end

      # @param overrides [Hash{Symbol=>Hash{Symbol=>String}}] specialty =>
      #   (suffix => clean value)
      def initialize(overrides = {})
        @overrides = overrides
      end

      # @return [Hash{Symbol=>String}, nil] suffix => clean value for +specialty+
      def overrides_for(specialty)
        @overrides[specialty]
      end

      # Yields every declared override so the build can verify each targets a
      # shredout that actually exists (completeness gate).
      def each_override
        return enum_for(:each_override) unless block_given?
        @overrides.each do |specialty, suffixes|
          suffixes.each do |suffix, value|
            yield specialty, suffix, value
          end
        end
      end

      def any?
        !@overrides.empty?
      end
    end
  end
end
