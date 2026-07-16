# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "date"

module GovCodes
  describe "AFSC versioned lookup" do
    before do
      @temp_dir = Dir.mktmpdir
      @release_date = Date.today
      afsc_dir = File.join(@temp_dir, "gov_codes", "afsc")
      # Dated today: `as_of: nil` (today) resolves to this synthetic release,
      # which the loader unions with the gem's shipped release.
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

    it "threads as_of into the enlisted lookup" do
      code = AFSC.find("1A172")
      _(code).must_be_instance_of AFSC::Enlisted::Code
      _(code.name).must_equal "Mobility Force Aviator"
      _(code.effective_date).must_equal @release_date
    end

    it "returns nil when as_of precedes the earliest release" do
      _(AFSC.find("1A172", as_of: "1900-01-01")).must_be_nil
    end

    it "threads as_of into search" do
      codes = AFSC.search("1A1X2", as_of: @release_date.iso8601).map(&:specialty)
      _(codes).must_include :"1A1X2"
    end

    it "returns no enlisted search results before the earliest release" do
      results = AFSC.search("1A1X2", as_of: "1900-01-01")
      _(results.select { |r| r.is_a?(AFSC::Enlisted::Code) }).must_equal []
    end
  end
end
