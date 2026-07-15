# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "date"
require "gov_codes/afsc"
require "gov_codes/afsc/enlisted"
require "gov_codes/afsc/releases"

module GovCodes
  module AFSC
    # Task 3: consumer-supplied acronym overlays. A dedicated tier that augments
    # an existing entry's :acronym WITHOUT clobbering the entry (the index merge
    # is shallow, so overlaying the whole entry would drop name/skill_levels/
    # shredouts). The consumer overlay wins over the source-extracted acronym.
    describe "Enlisted acronym overlay" do
      before do
        @temp_dir = Dir.mktmpdir
        release_dir = File.join(@temp_dir, "gov_codes", "afsc", "releases", "dafecd", "2025-10-31")
        FileUtils.mkdir_p(release_dir)
        # Flat SPECIALTY => ACRONYM map. 1Z1X1 (Pararescue) ships no acronym;
        # 1Z3X1 ships "TACP" and must be overridden by the consumer overlay.
        File.write(File.join(release_dir, "acronyms.yml"), <<~YAML)
          :"1Z1X1": PJ
          :"1Z3X1": OVERRIDDEN
          :"9Z9X9": GHOST
        YAML

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

      it "populates a missing acronym from the consumer overlay" do
        _(Enlisted.find("1Z1X1").acronym).must_equal "PJ"
      end

      it "leaves the entry's name, skill levels, and shredouts intact" do
        code = Enlisted.find("1Z1X1")
        _(code.name).must_equal "Pararescue"
        _(code.specialty_name).must_equal "Pararescue"
        # The concrete skill ladder still resolves through the same entry.
        _(Enlisted.find("1Z151").skill_level_name).wont_be_nil

        index = Releases.enlisted_index(lookup: $LOAD_PATH)
        _(index[:"1Z1X1"][:skill_levels].keys).must_equal [1, 3, 5, 7, 9]
        _(index[:"1Z1X1"][:shredouts]).must_equal({})
        _(index[:"1Z1X1"][:name]).must_equal "Pararescue"
      end

      it "lets the consumer overlay win over a shipped acronym" do
        _(Enlisted.find("1Z3X1").acronym).must_equal "OVERRIDDEN"
      end

      it "resolves the overlay for the release in effect on as_of" do
        _(Enlisted.find("1Z1X1", as_of: "2025-11-01").acronym).must_equal "PJ"
      end

      it "only augments existing entries (never creates a specialty)" do
        index = Releases.enlisted_index(lookup: $LOAD_PATH)
        _(index.key?(:"9Z9X9")).must_equal false
      end
    end

    # Officer/RI are unversioned: a single non-dated overlay each, a flat map
    # keyed by the code, loaded from the load path and applied in find.
    describe "Officer acronym overlay" do
      before do
        @temp_dir = Dir.mktmpdir
        afsc_dir = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(afsc_dir)
        File.write(File.join(afsc_dir, "officer_acronyms.yml"), <<~YAML)
          :"11MX": MOBPLT
        YAML

        $LOAD_PATH.unshift(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      after do
        $LOAD_PATH.delete(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      it "populates the officer acronym from the consumer overlay" do
        _(Officer.find("11MX").acronym).must_equal "MOBPLT"
      end

      it "leaves the officer name intact" do
        _(Officer.find("11MX").name).must_equal "Mobility pilot"
      end

      it "returns a nil acronym for a code absent from the overlay" do
        _(Officer.find("11BX").acronym).must_be_nil
      end
    end

    describe "RI acronym overlay" do
      before do
        @temp_dir = Dir.mktmpdir
        afsc_dir = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(afsc_dir)
        File.write(File.join(afsc_dir, "ri_acronyms.yml"), <<~YAML)
          :"8A400": TMC
        YAML

        $LOAD_PATH.unshift(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      after do
        $LOAD_PATH.delete(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      it "populates the ri acronym from the consumer overlay" do
        _(RI.find("8A400").acronym).must_equal "TMC"
      end

      it "leaves the ri name intact" do
        _(RI.find("8A400").name).must_equal "Talent management consultant"
      end
    end
  end
end
