require "date"
require "yaml"

module GovCodes
  module AFSC
    # Loads the versioned release manifest and per-release specialty index for a
    # publication (DAFECD enlisted, DAFOCD officer), and resolves the release in
    # effect on a given date. Both publications share this resolve/merge/cache
    # machinery and are resolved independently (their release dates may diverge).
    #
    # See docs/plans/2026-07-08-afsc-pdf-representation-design.md
    # "Versioning by document release".
    #
    # Storage layout (per release):
    #   lib/gov_codes/afsc/releases.yml                          # manifest
    #   lib/gov_codes/afsc/releases/dafecd/<date>/enlisted.yml   # enlisted index
    #   lib/gov_codes/afsc/releases/dafocd/<date>/officer.yml    # officer index
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
      ENLISTED_PUBLICATION = "dafecd"
      # Publication key for the officer directory (DAFOCD).
      OFFICER_PUBLICATION = "dafocd"

      class << self
        def manifest(lookup: $LOAD_PATH)
          manifest_cache[cache_key(lookup)] ||= load_manifest(lookup)
        end

        def enlisted_index(as_of: nil, lookup: $LOAD_PATH)
          release_index(ENLISTED_PUBLICATION, "enlisted.yml", as_of: as_of, lookup: lookup)
        end

        def officer_index(as_of: nil, lookup: $LOAD_PATH)
          release_index(OFFICER_PUBLICATION, "officer.yml", as_of: as_of, lookup: lookup)
        end

        # Resolve the effective date for +publication+ (defaults to enlisted).
        # Publications are resolved independently: an officer release date never
        # moves the enlisted latest date and vice versa.
        def effective_date_for(as_of: nil, lookup: $LOAD_PATH, publication: ENLISTED_PUBLICATION)
          release = resolve_release(publication, as_of: as_of, lookup: lookup)
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

        # Resolve, merge, and cache the release index for +publication+. The
        # cache key includes the publication and index filename so enlisted and
        # officer indexes never collide.
        def release_index(publication, index_file, as_of:, lookup:)
          key = [publication, index_file, to_date(as_of), cache_key(lookup)]
          index_cache[key] ||= load_release_index(publication, index_file, as_of: as_of, lookup: lookup)
        end

        def resolve_release(publication, as_of:, lookup:)
          releases = release_list(lookup, publication)
          return nil if releases.empty?

          target = to_date(as_of)
          return releases.last if target.nil?

          releases.reverse.find { |r| r[:date] <= target }
        end

        # Releases for +publication+ from the manifest, each annotated with a
        # parsed :date and the :dir name used to locate its index, sorted
        # ascending by date.
        def release_list(lookup, publication)
          entries = manifest(lookup: lookup)[publication.to_sym] || []
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

        def load_release_index(publication, index_file, as_of:, lookup:)
          release = resolve_release(publication, as_of: as_of, lookup: lookup)
          return {} unless release

          merged = {}
          parts = ["gov_codes", "afsc", "releases", publication, release[:dir], index_file]
          each_yaml(lookup, parts) { |data| merged.merge!(data) }
          apply_acronym_overlay(merged, publication, release, lookup)
          merged
        end

        # Apply the consumer acronym overlay (Task 3, "dedicated tier"): a flat
        # SPECIALTY => ACRONYM map at releases/<pub>/<dir>/acronyms.yml, resolved
        # for the SAME release as the index and merged across the load path
        # (consumer-loaded-last wins). Applied ONLY to specialties already in the
        # index, so it sets an entry's :acronym without ever replacing the entry
        # (the index merge above is shallow — overlaying whole entries here would
        # drop name/skill_levels/shredouts). The consumer overlay wins over the
        # source-extracted acronym shipped in the index. The gem ships no
        # acronyms.yml; an absent overlay leaves the index unchanged. Resolved per
        # release, so overlays never leak across document dates or publications.
        def apply_acronym_overlay(merged, publication, release, lookup)
          overlay = {}
          parts = ["gov_codes", "afsc", "releases", publication, release[:dir], "acronyms.yml"]
          each_yaml(lookup, parts) { |data| overlay.merge!(data) }
          overlay.each do |specialty, acronym|
            entry = merged[specialty]
            entry[:acronym] = acronym if entry
          end
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
