# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "date"
require "gov_codes/afsc"
require "gov_codes/afsc/enlisted"
require "gov_codes/afsc/officer"
require "gov_codes/afsc/releases"

module GovCodes
  module AFSC
    # The officer isolation guarantee, mirroring the enlisted suite in
    # find_by_acronym_test.rb: dated overlays must not leak across DAFOCD release
    # dates, forward (.acronym) or reverse (find_by_acronym), even after querying
    # the other date (cache cross-contamination).
    describe "officer acronym overlays are scoped per release date" do
      before do
        @temp_dir = Dir.mktmpdir
        base = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(base)
        # Add a second DAFOCD release (2026-04-30) alongside the shipped 2025-10-31.
        File.write(File.join(base, "releases.yml"), <<~YAML)
          :dafocd:
          - :effective_date: '2026-04-30'
            :version_label: test
            :source: test
            :name: Test
        YAML
        oct = File.join(base, "releases", "dafocd", "2025-10-31")
        apr = File.join(base, "releases", "dafocd", "2026-04-30")
        FileUtils.mkdir_p(oct)
        FileUtils.mkdir_p(apr)
        # The 2026 release brings its own 16FX index entry.
        File.write(File.join(apr, "officer.yml"), <<~YAML)
          :"16FX":
            :name: Foreign Area Officer (FAO)
            :career_field: :"16"
            :qual_levels: {}
            :shredouts: {}
        YAML
        # Same specialty, DIFFERENT acronym per release.
        File.write(File.join(oct, "acronyms.yml"), %(:"16FX": FAOX\n))
        File.write(File.join(apr, "acronyms.yml"), %(:"16FX": FAOY\n))
        $LOAD_PATH.unshift(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
        Releases.reset!
      end

      after do
        $LOAD_PATH.delete(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
        Releases.reset!
      end

      it "forward: each date resolves its own overlay" do
        _(AFSC.find("16FX", as_of: "2025-11-01").acronym).must_equal "FAOX"
        _(AFSC.find("16FX", as_of: "2026-05-01").acronym).must_equal "FAOY"
      end

      it "forward: no leak after querying the other date" do
        _(AFSC.find("16FX", as_of: "2026-05-01").acronym).must_equal "FAOY"
        _(AFSC.find("16FX", as_of: "2025-11-01").acronym).must_equal "FAOX"
        _(AFSC.find("16FX", as_of: "2026-05-01").acronym).must_equal "FAOY"
      end

      it "reverse: find_by_acronym is scoped per date" do
        _(AFSC.find_by_acronym("FAOX", as_of: "2025-11-01").specialty).must_equal :"16FX"
        _(AFSC.find_by_acronym("FAOY", as_of: "2026-05-01").specialty).must_equal :"16FX"
        # An acronym only defined in the OTHER release must not resolve here.
        _(AFSC.find_by_acronym("FAOY", as_of: "2025-11-01")).must_be_nil
        _(AFSC.find_by_acronym("FAOX", as_of: "2026-05-01")).must_be_nil
      end
    end

    # Publications resolve independently: an officer overlay must never affect an
    # enlisted lookup and vice versa, even when keyed by the same string.
    describe "officer and enlisted overlays resolve independently" do
      before do
        @temp_dir = Dir.mktmpdir
        base = File.join(@temp_dir, "gov_codes", "afsc")
        off = File.join(base, "releases", "dafocd", "2025-10-31")
        enl = File.join(base, "releases", "dafecd", "2025-10-31")
        FileUtils.mkdir_p(off)
        FileUtils.mkdir_p(enl)
        File.write(File.join(off, "acronyms.yml"), %(:"16FX": OFFONLY\n))
        File.write(File.join(enl, "acronyms.yml"), %(:"1Z1X1": ENLONLY\n))
        $LOAD_PATH.unshift(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
        Releases.reset!
      end

      after do
        $LOAD_PATH.delete(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
        Releases.reset!
      end

      it "applies the officer overlay only to officer lookups" do
        _(Officer.find("16FX").acronym).must_equal "OFFONLY"
        # The enlisted tier never sees the officer overlay.
        _(Enlisted.find_by_acronym("OFFONLY")).must_be_nil
      end

      it "applies the enlisted overlay only to enlisted lookups" do
        _(Enlisted.find("1Z1X1").acronym).must_equal "ENLONLY"
        # The officer tier never sees the enlisted overlay.
        _(Officer.find_by_acronym("ENLONLY")).must_be_nil
      end

      it "resolves each publication's latest effective date independently" do
        _(Releases.effective_date_for(as_of: nil, lookup: $LOAD_PATH,
          publication: Releases::ENLISTED_PUBLICATION)).must_equal Date.new(2025, 10, 31)
        _(Releases.effective_date_for(as_of: nil, lookup: $LOAD_PATH,
          publication: Releases::OFFICER_PUBLICATION)).must_equal Date.new(2025, 10, 31)
      end
    end
  end
end
