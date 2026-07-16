# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "date"
require "gov_codes/afsc/releases"

module GovCodes
  module AFSC
    describe Releases do
      before do
        @temp_dir = Dir.mktmpdir
        release_dir = File.join(@temp_dir, "gov_codes", "afsc", "releases", "dafecd")
        afsc_dir = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(afsc_dir)
        FileUtils.mkdir_p(File.join(release_dir, "2025-04-30"))
        FileUtils.mkdir_p(File.join(release_dir, "2025-10-31"))

        File.write(File.join(afsc_dir, "releases.yml"), <<~YAML)
          :dafecd:
          - :effective_date: '2025-04-30'
            :version_label: v3.4
            :source: synthetic-apr.pdf
            :name: Synthetic April Directory
          - :effective_date: '2025-10-31'
            :version_label: v3.5
            :source: synthetic-oct.pdf
            :name: Synthetic October Directory
        YAML

        File.write(File.join(release_dir, "2025-04-30", "enlisted.yml"), <<~YAML)
          :"9Y9X9":
            :name: Apr Synthetic
            :career_field: :"9Y"
            :skill_levels: {}
            :shredouts: {}
        YAML

        File.write(File.join(release_dir, "2025-10-31", "enlisted.yml"), <<~YAML)
          :"9Z9X9":
            :name: Oct Synthetic
            :career_field: :"9Z"
            :skill_levels: {}
            :shredouts: {}
        YAML
      end

      after do
        FileUtils.rm_rf(@temp_dir)
        Releases.reset!
      end

      describe ".manifest" do
        it "merges the release manifest from the lookup path" do
          manifest = Releases.manifest(lookup: [@temp_dir])
          dates = manifest[:dafecd].map { |r| r[:effective_date] }
          _(dates).must_include "2025-04-30"
          _(dates).must_include "2025-10-31"
        end
      end

      describe ".enlisted_index" do
        it "resolves the latest release when as_of is nil" do
          index = Releases.enlisted_index(as_of: nil, lookup: [@temp_dir])
          _(index.key?(:"9Z9X9")).must_equal true
          _(index.key?(:"9Y9X9")).must_equal false
        end

        it "resolves the release effective on the given date" do
          index = Releases.enlisted_index(as_of: "2025-10-31", lookup: [@temp_dir])
          _(index.key?(:"9Z9X9")).must_equal true
          _(index.key?(:"9Y9X9")).must_equal false
        end

        it "resolves the prior release for a date between releases" do
          index = Releases.enlisted_index(as_of: "2025-05-01", lookup: [@temp_dir])
          _(index.key?(:"9Y9X9")).must_equal true
          _(index.key?(:"9Z9X9")).must_equal false
        end

        it "returns an empty hash for a date before the earliest release" do
          index = Releases.enlisted_index(as_of: "2025-01-01", lookup: [@temp_dir])
          _(index).must_equal({})
        end

        it "accepts a Date object for as_of" do
          index = Releases.enlisted_index(as_of: Date.new(2025, 5, 1), lookup: [@temp_dir])
          _(index.key?(:"9Y9X9")).must_equal true
        end
      end

      describe ".effective_date_for" do
        it "returns the latest release date when as_of is nil" do
          _(Releases.effective_date_for(as_of: nil, lookup: [@temp_dir]))
            .must_equal Date.new(2025, 10, 31)
        end

        it "returns the resolved release date for a date between releases" do
          _(Releases.effective_date_for(as_of: "2025-05-01", lookup: [@temp_dir]))
            .must_equal Date.new(2025, 4, 30)
        end

        it "returns nil for a date before the earliest release" do
          _(Releases.effective_date_for(as_of: "2025-01-01", lookup: [@temp_dir]))
            .must_be_nil
        end
      end

      describe "invalid as_of" do
        it "raises a clear ArgumentError naming the bad value" do
          error = _ { Releases.enlisted_index(as_of: "not-a-date", lookup: [@temp_dir]) }
            .must_raise ArgumentError
          _(error.message).must_include "not-a-date"
          _(error.message).must_include "as_of"
        end

        it "raises for an invalid as_of in effective_date_for" do
          _ { Releases.effective_date_for(as_of: "nonsense", lookup: [@temp_dir]) }
            .must_raise ArgumentError
        end
      end
    end

    # DEC-004: a consumer manifest must MERGE its releases into the shipped list
    # (union by effective_date), not replace it. Adding a release must not hide
    # the gem's shipped 2025-10-31 release. A release dated in the future must
    # not take effect early just because it is the most recently added one --
    # `as_of: nil` (today) keeps resolving the shipped release until the future
    # release's own effective_date actually arrives.
    describe "Releases manifest merging" do
      before do
        @temp_dir = Dir.mktmpdir
        afsc_dir = File.join(@temp_dir, "gov_codes", "afsc")
        future_dir = File.join(afsc_dir, "releases", "dafecd", "2099-12-31")
        FileUtils.mkdir_p(future_dir)

        # Consumer lists ONLY their own (future) release, omitting the shipped one.
        File.write(File.join(afsc_dir, "releases.yml"), <<~YAML)
          :dafecd:
          - :effective_date: '2099-12-31'
            :version_label: future
            :source: synthetic-future.pdf
            :name: Synthetic Future Directory
        YAML

        File.write(File.join(future_dir, "enlisted.yml"), <<~YAML)
          :"9Q9X9":
            :name: Future Synthetic
            :career_field: :"9Q"
            :skill_levels: {}
            :shredouts: {}
        YAML
      end

      after do
        FileUtils.rm_rf(@temp_dir)
        Releases.reset!
      end

      it "unions the consumer release list with the shipped list" do
        dates = Releases.manifest(lookup: [@temp_dir])[:dafecd].map { |r| r[:effective_date] }
        _(dates).must_include "2025-10-31" # shipped, not hidden
        _(dates).must_include "2099-12-31" # consumer-added
      end

      it "keeps the shipped release resolvable after a consumer adds a release" do
        index = Releases.enlisted_index(as_of: "2025-11-01", lookup: [@temp_dir])
        _(index.key?(:"1A1X2")).must_equal true
        _(index.dig(:"1A1X2", :name)).must_equal "Mobility Force Aviator"
      end

      it "does not resolve a future release before its effective_date arrives" do
        index = Releases.enlisted_index(as_of: nil, lookup: [@temp_dir])
        _(index.key?(:"9Q9X9")).must_equal false
        _(index.key?(:"1A1X2")).must_equal true # still the shipped release
        _(Releases.effective_date_for(as_of: nil, lookup: [@temp_dir]))
          .must_equal Date.new(2025, 10, 31)
      end

      it "resolves the future release once as_of reaches its effective_date" do
        index = Releases.enlisted_index(as_of: "2099-12-31", lookup: [@temp_dir])
        _(index.key?(:"9Q9X9")).must_equal true
        _(Releases.effective_date_for(as_of: "2099-12-31", lookup: [@temp_dir]))
          .must_equal Date.new(2099, 12, 31)
      end
    end

    # The officer (DAFOCD) publication reuses the same resolve/merge/cache
    # machinery as enlisted (DAFECD) but reads officer.yml under releases/dafocd.
    # Dated today (rather than the shipped 2025-10-31) so `as_of: nil` resolves
    # this synthetic release instead of the real 130-entry shipped index, keeping
    # these assertions self-contained.
    describe "Releases officer index" do
      before do
        @temp_dir = Dir.mktmpdir
        @release_date = Date.today
        base = File.join(@temp_dir, "gov_codes", "afsc")
        release_dir = File.join(base, "releases", "dafocd", @release_date.iso8601)
        FileUtils.mkdir_p(release_dir)

        File.write(File.join(base, "releases.yml"), <<~YAML)
          :dafocd:
          - :effective_date: '#{@release_date.iso8601}'
            :version_label: test
            :source: synthetic-officer.pdf
            :name: Synthetic Officer Directory
        YAML

        File.write(File.join(release_dir, "officer.yml"), <<~YAML)
          :"19ZX":
            :name: Special Warfare
            :career_field: :"19"
            :qual_levels:
              3:
                :code: 19Z3
                :title: Qualified
            :shredouts:
              :B: Tactical Air Control Party Officer
            :shredout_acronyms:
              :B: TACPO
          :"16FX":
            :name: Foreign Area Officer (FAO)
            :acronym: FAO
            :career_field: :"16"
            :qual_levels: {}
            :shredouts: {}
        YAML
      end

      after do
        FileUtils.rm_rf(@temp_dir)
        Releases.reset!
      end

      it "resolves the officer index for the latest release" do
        index = Releases.officer_index(as_of: nil, lookup: [@temp_dir])
        _(index.key?(:"19ZX")).must_equal true
        _(index.dig(:"19ZX", :name)).must_equal "Special Warfare"
        _(index.dig(:"19ZX", :shredout_acronyms, :B)).must_equal "TACPO"
      end

      it "resolves the officer effective date via the officer publication" do
        _(Releases.effective_date_for(as_of: nil, lookup: [@temp_dir],
          publication: Releases::OFFICER_PUBLICATION))
          .must_equal @release_date
      end

      it "resolves each publication's effective date independently" do
        # The officer manifest addition must not move the enlisted latest date.
        _(Releases.effective_date_for(as_of: nil, lookup: [@temp_dir]))
          .must_equal Date.new(2025, 10, 31)
      end

      it "returns an empty index before the earliest officer release" do
        _(Releases.officer_index(as_of: "1900-01-01", lookup: [@temp_dir]))
          .must_equal({})
      end
    end

    # Officer per-release acronym overlay: a flat SPECIALTY => ACRONYM map at
    # releases/dafocd/<date>/acronyms.yml, resolved for the same release as the
    # index, augmenting :acronym on existing entries only.
    describe "Releases officer acronym overlay" do
      before do
        @temp_dir = Dir.mktmpdir
        release_date = Date.today
        base = File.join(@temp_dir, "gov_codes", "afsc")
        release_dir = File.join(base, "releases", "dafocd", release_date.iso8601)
        FileUtils.mkdir_p(release_dir)

        File.write(File.join(base, "releases.yml"), <<~YAML)
          :dafocd:
          - :effective_date: '#{release_date.iso8601}'
            :version_label: test
            :source: synthetic-officer.pdf
            :name: Synthetic Officer Directory
        YAML

        File.write(File.join(release_dir, "officer.yml"), <<~YAML)
          :"16FX":
            :name: Foreign Area Officer (FAO)
            :acronym: FAO
            :career_field: :"16"
            :qual_levels: {}
            :shredouts: {}
        YAML

        File.write(File.join(release_dir, "acronyms.yml"), <<~YAML)
          :"16FX": OVERRIDDEN
          :"99ZX": GHOST
        YAML
      end

      after do
        FileUtils.rm_rf(@temp_dir)
        Releases.reset!
      end

      it "lets the consumer overlay win over the shipped specialty acronym" do
        index = Releases.officer_index(as_of: nil, lookup: [@temp_dir])
        _(index.dig(:"16FX", :acronym)).must_equal "OVERRIDDEN"
      end

      it "only augments existing entries (never creates a specialty)" do
        index = Releases.officer_index(as_of: nil, lookup: [@temp_dir])
        _(index.key?(:"99ZX")).must_equal false
      end

      it "leaves the entry's name and shredouts intact" do
        index = Releases.officer_index(as_of: nil, lookup: [@temp_dir])
        _(index.dig(:"16FX", :name)).must_equal "Foreign Area Officer (FAO)"
      end
    end

    # RI/SDI index resolves for either publication via the shared resolve/merge/
    # cache machinery, and the generic per-release acronym overlay reaches ri.yml
    # entries exactly as it reaches enlisted.yml/officer.yml entries.
    describe "Releases ri index" do
      before do
        @temp_dir = Dir.mktmpdir
        @release_date = Date.today
        base = File.join(@temp_dir, "gov_codes", "afsc")
        enl = File.join(base, "releases", "dafecd", @release_date.iso8601)
        off = File.join(base, "releases", "dafocd", @release_date.iso8601)
        FileUtils.mkdir_p(enl)
        FileUtils.mkdir_p(off)

        File.write(File.join(base, "releases.yml"), <<~YAML)
          :dafecd:
          - :effective_date: '#{@release_date.iso8601}'
            :version_label: test
            :source: synthetic-enl.pdf
            :name: Synthetic Enlisted Directory
          :dafocd:
          - :effective_date: '#{@release_date.iso8601}'
            :version_label: test
            :source: synthetic-off.pdf
            :name: Synthetic Officer Directory
        YAML

        File.write(File.join(enl, "ri.yml"), <<~YAML)
          :"9Z200":
            :name: Enlisted RI
          :"8R300":
            :name: Third-Tier Recruiter
            :shredouts:
              :A: Flight Chief
        YAML

        File.write(File.join(off, "ri.yml"), <<~YAML)
          :"90G0":
            :name: Officer RI
        YAML

        # Per-release acronym overlay must reach ri.yml entries too.
        File.write(File.join(enl, "acronyms.yml"), %(:"9Z200": ENLRI\n))
        File.write(File.join(off, "acronyms.yml"), %(:"90G0": OFFRI\n))
      end

      after do
        FileUtils.rm_rf(@temp_dir)
        Releases.reset!
      end

      it "resolves the enlisted ri index by publication" do
        index = Releases.ri_index(as_of: nil, lookup: [@temp_dir],
          publication: Releases::ENLISTED_PUBLICATION)
        _(index.dig(:"9Z200", :name)).must_equal "Enlisted RI"
        _(index.dig(:"8R300", :shredouts, :A)).must_equal "Flight Chief"
      end

      it "resolves the officer ri index by publication" do
        index = Releases.ri_index(as_of: nil, lookup: [@temp_dir],
          publication: Releases::OFFICER_PUBLICATION)
        _(index.dig(:"90G0", :name)).must_equal "Officer RI"
      end

      it "defaults to the enlisted publication" do
        index = Releases.ri_index(as_of: nil, lookup: [@temp_dir])
        _(index.key?(:"9Z200")).must_equal true
        _(index.key?(:"90G0")).must_equal false
      end

      it "applies the generic per-release acronym overlay to ri entries" do
        enl = Releases.ri_index(as_of: nil, lookup: [@temp_dir],
          publication: Releases::ENLISTED_PUBLICATION)
        off = Releases.ri_index(as_of: nil, lookup: [@temp_dir],
          publication: Releases::OFFICER_PUBLICATION)
        _(enl.dig(:"9Z200", :acronym)).must_equal "ENLRI"
        _(off.dig(:"90G0", :acronym)).must_equal "OFFRI"
      end

      it "returns an empty index before the earliest release" do
        _(Releases.ri_index(as_of: "1900-01-01", lookup: [@temp_dir],
          publication: Releases::ENLISTED_PUBLICATION)).must_equal({})
      end
    end
  end
end
