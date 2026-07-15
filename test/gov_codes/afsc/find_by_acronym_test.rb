# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "date"
require "gov_codes/afsc"
require "gov_codes/afsc/releases"

module GovCodes
  module AFSC
    describe "AFSC.find_by_acronym (shipped, source-verified)" do
      it "resolves a specialty by its acronym" do
        code = AFSC.find_by_acronym("RAWS")
        _(code).must_be_instance_of Enlisted::Code
        _(code.specialty).must_equal :"1C8X3"
        _(code.acronym).must_equal "RAWS"
      end

      it "is case-insensitive" do
        _(AFSC.find_by_acronym("raws").specialty).must_equal :"1C8X3"
        _(AFSC.find_by_acronym("TaCp").specialty).must_equal :"1Z3X1"
      end

      it "returns nil for an unknown or empty acronym" do
        _(AFSC.find_by_acronym("ZZZ")).must_be_nil
        _(AFSC.find_by_acronym("")).must_be_nil
      end

      it "carries the resolved release effective_date" do
        _(AFSC.find_by_acronym("RAWS").effective_date).must_equal Date.new(2025, 10, 31)
      end
    end

    describe "AFSC.find_by_acronym (consumer overlay)" do
      before do
        @temp_dir = Dir.mktmpdir
        rel = File.join(@temp_dir, "gov_codes", "afsc", "releases", "dafecd", "2025-10-31")
        FileUtils.mkdir_p(rel)
        File.write(File.join(rel, "acronyms.yml"), %(:"1Z1X1": PJ\n))
        off = File.join(@temp_dir, "gov_codes", "afsc", "releases", "dafocd", "2025-10-31")
        FileUtils.mkdir_p(off)
        File.write(File.join(off, "acronyms.yml"), %(:"11MX": MOBPLT\n))
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

      it "resolves an enlisted specialty by a consumer-overlay acronym" do
        code = AFSC.find_by_acronym("PJ")
        _(code.specialty).must_equal :"1Z1X1"
        _(code.name).must_equal "Pararescue"
      end

      it "resolves an officer code by a consumer-overlay acronym" do
        code = AFSC.find_by_acronym("MOBPLT")
        _(code).must_be_instance_of Officer::Code
        _(code.specific_afsc).must_equal :"11MX"
      end
    end

    # The key isolation guarantee: dated overlays must not leak across document
    # release dates, in either the forward (.acronym) or reverse (find_by_acronym)
    # direction, even after querying the other date (cache cross-contamination).
    describe "acronym overlays are scoped per release date" do
      before do
        @temp_dir = Dir.mktmpdir
        base = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(base)
        # Add a second release (2026-04-30) alongside the shipped 2025-10-31.
        File.write(File.join(base, "releases.yml"), <<~YAML)
          :dafecd:
          - :effective_date: '2026-04-30'
            :version_label: test
            :source: test
            :name: Test
        YAML
        oct = File.join(base, "releases", "dafecd", "2025-10-31")
        apr = File.join(base, "releases", "dafecd", "2026-04-30")
        FileUtils.mkdir_p(oct)
        FileUtils.mkdir_p(apr)
        # The 2026 release brings its own 1Z1X1 index entry.
        File.write(File.join(apr, "enlisted.yml"), <<~YAML)
          :"1Z1X1":
            :name: Pararescue
            :career_field: :"1Z"
            :skill_levels:
              7:
                :code: 1Z171
                :title: Craftsman
            :shredouts: {}
        YAML
        # Same specialty, DIFFERENT acronym per release.
        File.write(File.join(oct, "acronyms.yml"), %(:"1Z1X1": PJ\n))
        File.write(File.join(apr, "acronyms.yml"), %(:"1Z1X1": PJX\n))
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
        _(AFSC.find("1Z1X1", as_of: "2025-11-01").acronym).must_equal "PJ"
        _(AFSC.find("1Z1X1", as_of: "2026-05-01").acronym).must_equal "PJX"
      end

      it "forward: no leak after querying the other date" do
        _(AFSC.find("1Z1X1", as_of: "2026-05-01").acronym).must_equal "PJX"
        _(AFSC.find("1Z1X1", as_of: "2025-11-01").acronym).must_equal "PJ"
        _(AFSC.find("1Z1X1", as_of: "2026-05-01").acronym).must_equal "PJX"
      end

      it "reverse: find_by_acronym is scoped per date" do
        _(AFSC.find_by_acronym("PJ", as_of: "2025-11-01").specialty).must_equal :"1Z1X1"
        _(AFSC.find_by_acronym("PJX", as_of: "2026-05-01").specialty).must_equal :"1Z1X1"
        # An acronym only defined in the OTHER release must not resolve here.
        _(AFSC.find_by_acronym("PJX", as_of: "2025-11-01")).must_be_nil
        _(AFSC.find_by_acronym("PJ", as_of: "2026-05-01")).must_be_nil
      end
    end
  end
end
