# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module GovCodes
  module AFSC
    # Exercises DEC-004 extensibility: a consumer may drop a release index onto
    # the load path to extend or override the shipped DAFECD release.
    describe Enlisted do
      before do
        @temp_dir = Dir.mktmpdir
        release_dir = File.join(@temp_dir, "gov_codes", "afsc", "releases", "dafecd", "2025-10-31")
        FileUtils.mkdir_p(release_dir)

        # No manifest here: the shipped manifest already lists 2025-10-31, so the
        # loader resolves that release and merges this index over the gem's.
        File.write(File.join(release_dir, "enlisted.yml"), <<~YAML)
          :"9Z9X9":
            :name: Custom Specialty
            :career_field: :"9Z"
            :skill_levels:
              7:
                :code: 9Z979
                :title: Craftsman
            :shredouts:
              :A: Custom Shredout
          :"1A1X2":
            :name: Overridden Aviator
            :career_field: :"1A"
            :skill_levels: {}
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
          code = Enlisted.find("9Z9X9")
          _(code).wont_be_nil
          _(code.specific_afsc.to_s).must_equal "9Z9X9"
          _(code.name).must_equal "Custom Specialty"
        end

        it "reads the skill-level title from the consumer index" do
          code = Enlisted.find("9Z979")
          _(code.skill_level_number).must_equal 7
          _(code.skill_level_name).must_equal "Craftsman"
        end

        it "resolves a consumer-supplied shredout" do
          code = Enlisted.find("9Z9X9A")
          _(code.shredout).must_equal :A
          _(code.shredout_name).must_equal "Custom Shredout"
          _(code.name).must_equal "Custom Shredout"
        end

        it "lets a consumer override a shipped specialty for the same release" do
          code = Enlisted.find("1A1X2")
          _(code.name).must_equal "Overridden Aviator"
        end

        it "still resolves a shipped specialty absent from the consumer index" do
          # 6C0X1 is only in the gem's shipped index; proving merge, not replace.
          code = Enlisted.find("6C0X1")
          _(code).wont_be_nil
          _(code.name).must_equal "Contracting"
        end

        it "routes through AFSC.find" do
          code = AFSC.find("9Z9X9")
          _(code).must_be_instance_of Enlisted::Code
          _(code.name).must_equal "Custom Specialty"
        end
      end
    end
  end
end
