# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "date"
require "gov_codes/afsc/enlisted"
require "gov_codes/afsc/releases"

module GovCodes
  module AFSC
    describe "Enlisted versioned lookup" do
      before do
        @temp_dir = Dir.mktmpdir
        @release_date = Date.today
        afsc_dir = File.join(@temp_dir, "gov_codes", "afsc")
        # Dated today so `as_of: nil` (today) resolves to this synthetic release
        # rather than the gem's shipped one (release lists are unioned across
        # the load path).
        release_dir = File.join(afsc_dir, "releases", "dafecd", @release_date.iso8601)
        FileUtils.mkdir_p(release_dir)

        File.write(File.join(afsc_dir, "releases.yml"), <<~YAML)
          :dafecd:
          - :effective_date: '#{@release_date.iso8601}'
            :version_label: test
            :source: synthetic.pdf
            :name: Synthetic Directory
        YAML

        File.write(File.join(release_dir, "enlisted.yml"), <<~YAML)
          :"1A1X2":
            :name: Mobility Force Aviator
            :career_field: :"1A"
            :skill_levels:
              7:
                :code: 1A172
                :title: Craftsman
            :shredouts:
              :A: C-5 Flight Engineer
              :Y: General
        YAML

        $LOAD_PATH.unshift(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      after do
        $LOAD_PATH.delete(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      it "resolves a concrete code against the versioned index" do
        code = Enlisted.find("1A172")
        _(code).wont_be_nil
        _(code.specialty).must_equal :"1A1X2"
        _(code.specialty_name).must_equal "Mobility Force Aviator"
        _(code.name).must_equal "Mobility Force Aviator"
        _(code.skill_level_number).must_equal 7
        _(code.skill_level_name).must_equal "Craftsman"
      end

      it "carries the release effective_date on the resolved code" do
        code = Enlisted.find("1A172")
        _(code.effective_date).must_equal @release_date
      end

      it "resolves a shredout name from the versioned index" do
        code = Enlisted.find("1A172Y")
        _(code.shredout).must_equal :Y
        _(code.shredout_name).must_equal "General"
        _(code.name).must_equal "General"
      end

      it "returns nil for an as_of before the earliest release" do
        _(Enlisted.find("1A172", as_of: "1900-01-01")).must_be_nil
      end

      it "resolves the same code for an as_of within the release window" do
        code = Enlisted.find("1A172", as_of: @release_date.iso8601)
        _(code.specialty_name).must_equal "Mobility Force Aviator"
        _(code.effective_date).must_equal @release_date
      end

      it "returns nil for a specialty absent from the release" do
        _(Enlisted.find("9Z9X9")).must_be_nil
      end

      describe "search over the versioned index" do
        it "emits the specialty and its shredout suffixes" do
          codes = Enlisted.search("1A1X2").map { |c| "#{c.specific_afsc}#{c.shredout}" }
          _(codes).must_include "1A1X2"
          _(codes).must_include "1A1X2A"
          _(codes).must_include "1A1X2Y"
        end

        it "carries the release effective_date on searched codes" do
          codes = Enlisted.search("1A1X2")
          _(codes).wont_be_empty
          codes.each { |c| _(c.effective_date).must_equal @release_date }
        end

        it "is case-insensitive" do
          _(Enlisted.search("1a1x2").map(&:specialty)).must_include :"1A1X2"
        end

        it "returns an empty array for an as_of before the earliest release" do
          _(Enlisted.search("1A1X2", as_of: "1900-01-01")).must_equal []
        end
      end
    end

    # A malformed consumer file on the load path must be skipped, not fatal:
    # the shipped release still resolves (graceful degradation).
    describe "Enlisted graceful degradation" do
      before do
        @temp_dir = Dir.mktmpdir
      end

      after do
        $LOAD_PATH.delete(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      def use_temp_load_path
        $LOAD_PATH.unshift(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      it "skips a malformed consumer release index and uses the shipped one" do
        release_dir = File.join(@temp_dir, "gov_codes", "afsc", "releases", "dafecd", "2025-10-31")
        FileUtils.mkdir_p(release_dir)
        File.write(File.join(release_dir, "enlisted.yml"), "invalid: yaml: content:")
        use_temp_load_path

        code = Enlisted.find("1A172")
        _(code).wont_be_nil
        _(code.name).must_equal "Mobility Force Aviator"
        _(code.effective_date).must_equal Date.new(2025, 10, 31)
      end

      it "skips a malformed consumer manifest and uses the shipped one" do
        afsc_dir = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(afsc_dir)
        File.write(File.join(afsc_dir, "releases.yml"), "invalid: yaml: content:")
        use_temp_load_path

        code = Enlisted.find("1A172")
        _(code).wont_be_nil
        _(code.name).must_equal "Mobility Force Aviator"
        _(code.effective_date).must_equal Date.new(2025, 10, 31)
      end
    end

    # M-1: equivalent as_of values (nil, the resolved Date, its string form) must
    # share one memo slot rather than accumulating separate entries.
    describe "Enlisted cache-key normalization" do
      before { AFSC.reset_data(lookup: $LOAD_PATH) }
      after { AFSC.reset_data(lookup: $LOAD_PATH) }

      it "shares a cache slot for equivalent as_of values" do
        latest_date = Releases.effective_date_for(as_of: nil)
        by_nil = Enlisted.find("1A172")
        by_date = Enlisted.find("1A172", as_of: latest_date)
        by_string = Enlisted.find("1A172", as_of: latest_date.to_s)

        _(by_date).must_be_same_as by_nil
        _(by_string).must_be_same_as by_nil
        _(by_nil.effective_date).must_equal latest_date
      end
    end

    # M-2: an unparseable as_of surfaces a clear ArgumentError, not a cryptic
    # Date::Error, from the public find API.
    describe "Enlisted invalid as_of" do
      after { AFSC.reset_data(lookup: $LOAD_PATH) }

      it "raises a clear ArgumentError naming the bad value" do
        error = _ { Enlisted.find("1A172", as_of: "not-a-date") }.must_raise ArgumentError
        _(error.message).must_include "not-a-date"
      end
    end
  end
end
