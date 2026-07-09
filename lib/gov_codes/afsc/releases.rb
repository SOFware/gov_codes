require "date"
require "yaml"

module GovCodes
  module AFSC
    # Loads the versioned DAFECD release manifest and per-release specialty
    # index, and resolves the release in effect on a given date.
    #
    # See docs/plans/2026-07-08-afsc-pdf-representation-design.md
    # "Versioning by document release".
    #
    # Storage layout (per release):
    #   lib/gov_codes/afsc/releases.yml                          # manifest
    #   lib/gov_codes/afsc/releases/dafecd/<date>/enlisted.yml   # index
    #
    # Resolution: releases are sorted ascending by effective_date. A given
    # `as_of` resolves to the release with the greatest effective_date <= as_of;
    # `as_of: nil` resolves to the latest release. A date before the earliest
    # shipped release resolves to no release (an empty index / nil date).
    #
    # Extensibility (DEC-004): both tiers merge across the load path (gem lib dir
    # first, then the load path). The manifest's per-publication release list is
    # unioned by effective_date -- a consumer releases.yml ADDS releases without
    # hiding the shipped ones, and a same-date entry from the load path wins. For
    # the resolved release, the release index found at each lookup path is merged,
    # so a consumer may drop gov_codes/afsc/releases/dafecd/<date>/enlisted.yml to
    # extend or override the shipped index.
    module Releases
      # Publication key for the enlisted directory (DAFECD).
      PUBLICATION = "dafecd"

      class << self
        def manifest(lookup: $LOAD_PATH)
          manifest_cache[cache_key(lookup)] ||= load_manifest(lookup)
        end

        def enlisted_index(as_of: nil, lookup: $LOAD_PATH)
          key = [to_date(as_of), cache_key(lookup)]
          index_cache[key] ||= load_enlisted_index(as_of: as_of, lookup: lookup)
        end

        def effective_date_for(as_of: nil, lookup: $LOAD_PATH)
          release = resolve_release(as_of: as_of, lookup: lookup)
          release && release[:date]
        end

        def reset!
          @manifest_cache = {}
          @index_cache = {}
        end

        private

        def manifest_cache
          @manifest_cache ||= {}
        end

        def index_cache
          @index_cache ||= {}
        end

        def cache_key(lookup)
          Array(lookup).dup
        end

        def to_date(as_of)
          return nil if as_of.nil?
          return as_of if as_of.is_a?(Date)
          Date.parse(as_of.to_s)
        rescue Date::Error
          raise ArgumentError,
            "invalid as_of #{as_of.inspect}: expected a Date or a parseable date string (e.g. \"2025-10-31\")"
        end

        # Ordered list of directories to search: the gem lib dir first, then the
        # provided lookup path. Deduplicated to avoid loading the same file twice.
        def lookup_paths(lookup)
          gem_lib_dir = File.expand_path("../..", __dir__)
          ([gem_lib_dir] + Array(lookup)).uniq
        end

        def resolve_release(as_of:, lookup:)
          releases = release_list(lookup)
          return nil if releases.empty?

          target = to_date(as_of)
          return releases.last if target.nil?

          releases.reverse.find { |r| r[:date] <= target }
        end

        # Releases from the manifest, each annotated with a parsed :date and the
        # :dir name used to locate its index, sorted ascending by date.
        def release_list(lookup)
          entries = manifest(lookup: lookup)[:dafecd] || []
          entries.filter_map do |entry|
            raw = entry[:effective_date]
            next unless raw

            date = raw.is_a?(Date) ? raw : Date.parse(raw.to_s)
            dir = raw.is_a?(Date) ? raw.strftime("%Y-%m-%d") : raw.to_s
            entry.merge(date: date, dir: dir)
          end.sort_by { |r| r[:date] }
        end

        def load_manifest(lookup)
          merged = {}
          each_yaml(lookup, ["gov_codes", "afsc", "releases.yml"]) do |data|
            merge_manifest!(merged, data)
          end
          merged
        end

        def load_enlisted_index(as_of:, lookup:)
          release = resolve_release(as_of: as_of, lookup: lookup)
          return {} unless release

          merged = {}
          parts = ["gov_codes", "afsc", "releases", PUBLICATION, release[:dir], "enlisted.yml"]
          each_yaml(lookup, parts) { |data| merged.merge!(data) }
          merged
        end

        # Merge a manifest hash into +acc+. Per-publication release lists are
        # unioned by effective_date (a same-date entry from a later-loaded file
        # wins); non-list values fall back to a plain overwrite.
        def merge_manifest!(acc, incoming)
          incoming.each do |publication, releases|
            acc[publication] = if acc[publication].is_a?(Array) && releases.is_a?(Array)
              union_releases(acc[publication], releases)
            else
              releases
            end
          end
          acc
        end

        def union_releases(base, overrides)
          by_date = {}
          (base + overrides).each do |entry|
            by_date[entry[:effective_date]] = entry if entry.is_a?(Hash)
          end
          by_date.values
        end

        # Yield each parsed YAML hash found at +parts+ across the lookup paths,
        # skipping missing files and malformed YAML (graceful degradation).
        def each_yaml(lookup, parts)
          lookup_paths(lookup).each do |dir|
            path = File.join(dir, *parts)
            next unless File.exist?(path)

            data = YAML.load_file(path, symbolize_names: true)
            yield data if data.is_a?(Hash)
          rescue Psych::SyntaxError, TypeError
            next
          end
        end
      end
    end
  end
end
