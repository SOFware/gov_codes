# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "date"
require "gov_codes/afsc"
require "gov_codes/afsc/enlisted"
require "gov_codes/afsc/officer"
require "gov_codes/afsc/ri"
require "gov_codes/afsc/releases"

module GovCodes
  module AFSC
    # The RI/SDI isolation guarantee, mirroring officer_isolation_test.rb: dated
    # RI overlays must not leak across DAFECD release dates, forward (.acronym via
    # RI.find / AFSC.find) or reverse (find_by_acronym), even after querying the
    # other date (cache cross-contamination). RI/SDI shares the same per-release
    # acronyms.yml overlay tier as enlisted/officer, so the same scoping must hold.
    describe "ri acronym overlays are scoped per release date" do
      before do
        @temp_dir = Dir.mktmpdir
        base = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(base)
        # Add a second DAFECD release (2026-04-30) alongside the shipped 2025-10-31.
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
        # The 2026 release brings its own 9Z200 RI entry (reused from the shipped
        # index, mirroring how officer_isolation_test.rb reuses 16FX).
        File.write(File.join(apr, "ri.yml"), <<~YAML)
          :"9Z200":
            :name: Special Warfare Mission Support Superintendent
        YAML
        # Same RI code, DIFFERENT acronym per release.
        File.write(File.join(oct, "acronyms.yml"), %(:"9Z200": RIX\n))
        File.write(File.join(apr, "acronyms.yml"), %(:"9Z200": RIY\n))
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
        _(AFSC.find("9Z200", as_of: "2025-11-01").acronym).must_equal "RIX"
        _(AFSC.find("9Z200", as_of: "2026-05-01").acronym).must_equal "RIY"
        # The RI entry point agrees with the AFSC dispatcher.
        _(RI.find("9Z200", as_of: "2025-11-01").acronym).must_equal "RIX"
        _(RI.find("9Z200", as_of: "2026-05-01").acronym).must_equal "RIY"
      end

      it "forward: no leak after querying the other date" do
        _(AFSC.find("9Z200", as_of: "2026-05-01").acronym).must_equal "RIY"
        _(AFSC.find("9Z200", as_of: "2025-11-01").acronym).must_equal "RIX"
        _(AFSC.find("9Z200", as_of: "2026-05-01").acronym).must_equal "RIY"
      end

      it "reverse: find_by_acronym is scoped per date" do
        _(AFSC.find_by_acronym("RIX", as_of: "2025-11-01").specific_ri).must_equal :"9Z200"
        _(AFSC.find_by_acronym("RIY", as_of: "2026-05-01").specific_ri).must_equal :"9Z200"
        _(RI.find_by_acronym("RIX", as_of: "2025-11-01").specific_ri).must_equal :"9Z200"
        _(RI.find_by_acronym("RIY", as_of: "2026-05-01").specific_ri).must_equal :"9Z200"
        # An acronym only defined in the OTHER release must not resolve here.
        _(AFSC.find_by_acronym("RIY", as_of: "2025-11-01")).must_be_nil
        _(AFSC.find_by_acronym("RIX", as_of: "2026-05-01")).must_be_nil
        _(RI.find_by_acronym("RIY", as_of: "2025-11-01")).must_be_nil
        _(RI.find_by_acronym("RIX", as_of: "2026-05-01")).must_be_nil
      end
    end

    # RI/SDI and enlisted/officer overlays resolve independently: the SAME per-
    # release acronyms.yml serves both the AFSC index and the RI index for a
    # publication, but each overlay entry only augments the index that actually
    # holds its code. An RI overlay must never affect an enlisted/officer lookup
    # and vice versa, even keyed in the same file.
    describe "ri and enlisted/officer overlays resolve independently" do
      before do
        @temp_dir = Dir.mktmpdir
        base = File.join(@temp_dir, "gov_codes", "afsc")
        enl = File.join(base, "releases", "dafecd", "2025-10-31")
        off = File.join(base, "releases", "dafocd", "2025-10-31")
        FileUtils.mkdir_p(enl)
        FileUtils.mkdir_p(off)
        # One overlay file per publication carries both an RI code and an AFSC
        # code. 9Z200/90G0 live only in ri.yml; 1Z1X1/16FX live only in the AFSC
        # index. Each key must augment only the index that holds it.
        File.write(File.join(enl, "acronyms.yml"), <<~YAML)
          :"9Z200": RIONLY
          :"1Z1X1": ENLONLY
        YAML
        File.write(File.join(off, "acronyms.yml"), <<~YAML)
          :"90G0": RIOFFONLY
          :"16FX": OFFONLY
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

      it "applies the enlisted RI overlay only to RI lookups" do
        _(RI.find("9Z200").acronym).must_equal "RIONLY"
        # The enlisted tier never sees the RI overlay.
        _(Enlisted.find_by_acronym("RIONLY")).must_be_nil
      end

      it "applies the enlisted overlay only to enlisted lookups" do
        _(Enlisted.find("1Z1X1").acronym).must_equal "ENLONLY"
        # The RI tier never sees the enlisted overlay.
        _(RI.find_by_acronym("ENLONLY")).must_be_nil
      end

      it "applies the officer RI overlay only to RI lookups" do
        _(RI.find("90G0").acronym).must_equal "RIOFFONLY"
        # The officer tier never sees the RI overlay.
        _(Officer.find_by_acronym("RIOFFONLY")).must_be_nil
      end

      it "applies the officer overlay only to officer lookups" do
        _(Officer.find("16FX").acronym).must_equal "OFFONLY"
        # The RI tier never sees the officer overlay.
        _(RI.find_by_acronym("OFFONLY")).must_be_nil
      end
    end
  end
end
