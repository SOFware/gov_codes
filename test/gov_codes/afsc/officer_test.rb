# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "date"

module GovCodes
  module AFSC
    # Exercises DEC-004 extensibility for the officer publication: a consumer may
    # drop a DAFOCD release index onto the load path to extend or override the
    # shipped release. Mirrors enlisted_test.rb.
    describe Officer do
      before do
        @temp_dir = Dir.mktmpdir
        release_dir = File.join(@temp_dir, "gov_codes", "afsc", "releases", "dafocd", "2025-10-31")
        FileUtils.mkdir_p(release_dir)

        # No manifest here: the shipped manifest already lists dafocd 2025-10-31,
        # so the loader resolves that release and merges this index over the gem's.
        File.write(File.join(release_dir, "officer.yml"), <<~YAML)
          :"99ZX":
            :name: Custom Specialty
            :career_field: :"99"
            :qual_levels:
              3:
                :code: 99Z3
                :title: Custom Qualified
            :shredouts:
              :A: Custom Shredout
          :"11MX":
            :name: Overridden Mobility Pilot
            :career_field: :"11"
            :qual_levels: {}
            :shredouts: {}
        YAML

        $LOAD_PATH.unshift(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      after do
        $LOAD_PATH.delete(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
        AFSC.reset_data(lookup: $LOAD_PATH)
      end

      describe "#find" do
        it "merges a consumer-supplied release index across the load path" do
          code = Officer.find("99ZX")
          _(code).wont_be_nil
          _(code.specialty).must_equal :"99ZX"
          _(code.specialty_name).must_equal "Custom Specialty"
          _(code.name).must_equal "Custom Specialty"
        end

        it "reads the qualification-level title from the consumer index" do
          code = Officer.find("99Z3")
          _(code.qualification_level_number).must_equal 3
          _(code.qualification_level_name).must_equal "Custom Qualified"
        end

        it "resolves a consumer-supplied shredout" do
          code = Officer.find("99ZXA")
          _(code.shredout).must_equal :A
          _(code.shredout_name).must_equal "Custom Shredout"
          _(code.name).must_equal "Custom Shredout"
        end

        it "lets a consumer override a shipped specialty for the same release" do
          code = Officer.find("11MX")
          _(code.name).must_equal "Overridden Mobility Pilot"
        end

        it "still resolves a shipped specialty absent from the consumer index" do
          # 11BX is only in the gem's shipped index; proving merge, not replace.
          code = Officer.find("11BX")
          _(code).wont_be_nil
          _(code.name).must_equal "Bomber Pilot"
        end

        it "routes through AFSC.find" do
          code = AFSC.find("99ZX")
          _(code).must_be_instance_of Officer::Code
          _(code.name).must_equal "Custom Specialty"
        end

        it "returns nil for an unknown officer code" do
          _(Officer.find("99QX")).must_be_nil
        end

        it "handles invalid code" do
          _(Officer.find("invalid")).must_be_nil
        end

        it "handles nil code" do
          _(Officer.find(nil)).must_be_nil
        end

        it "handles empty code" do
          _(Officer.find("")).must_be_nil
        end
      end
    end

    # A malformed consumer file on the load path must be skipped, not fatal: the
    # shipped release still resolves (graceful degradation). Mirrors the enlisted
    # graceful-degradation suite.
    describe "Officer graceful degradation" do
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
        release_dir = File.join(@temp_dir, "gov_codes", "afsc", "releases", "dafocd", "2025-10-31")
        FileUtils.mkdir_p(release_dir)
        File.write(File.join(release_dir, "officer.yml"), "invalid: yaml: content:")
        use_temp_load_path

        code = Officer.find("11MX")
        _(code).wont_be_nil
        _(code.name).must_equal "Mobility Pilot"
        _(code.effective_date).must_equal Date.new(2025, 10, 31)
      end
    end
  end
end
