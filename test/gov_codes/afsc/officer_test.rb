# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

module GovCodes
  module AFSC
    describe Officer do
      before do
        # Create a temporary directory for our test YAML file
        @temp_dir = Dir.mktmpdir
        @gov_codes_dir = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(@gov_codes_dir)
        @temp_yaml_path = File.join(@gov_codes_dir, "officer.yml")

        # Create a sample YAML file with test data
        File.write(@temp_yaml_path, <<~YAML)
          11B:
            name: Test Operations Officer
        YAML

        # Get the path to the gem's lib directory
        @lib_dir = File.expand_path("../../../../lib", __FILE__)

        # Add the temporary directory to the load path
        $LOAD_PATH.unshift @temp_dir
      end

      after do
        # Remove the temporary directory from the load path
        $LOAD_PATH.delete(@temp_dir)
        # Clean up the temporary directory
        FileUtils.rm_rf(@temp_dir)
      end

      describe "#data" do
        it "merges YAML files from lookup path" do
          data = Officer.data(lookup: [$LOAD_PATH.first])

          # Verify that our test data is present
          _(data[:"11B"]).wont_be :nil?
          _(data.dig(:"11B", :name)).must_equal "Test Operations Officer"
        end

        it "works with custom lookup path" do
          data = Officer.data(lookup: [@temp_dir])
          _(data.dig(:"11B", :name)).must_equal "Test Operations Officer"
        end
      end

      describe "#find" do
        it "finds valid code" do
          # Use reset_data with custom lookup to override the real data
          Officer.reset_data(lookup: [@temp_dir])

          code = Officer.find("11B3")

          _(code).wont_be :nil?
          _(code.career_group).must_equal :"11"
          _(code.functional_area).must_equal :B
          _(code.qualification_level).must_equal :"3"
          _(code.shredout).must_be :nil?
          _(code.name).must_equal "Test Operations Officer"
        end

        it "finds code with shredout" do
          # Use reset_data with custom lookup to override the real data
          Officer.reset_data(lookup: [@temp_dir])

          code = Officer.find("11B3X")

          _(code).wont_be :nil?
          _(code.shredout).must_equal :X
          _(code.name).must_equal "Test Operations Officer"
        end

        it "handles invalid code" do
          _(Officer.find("invalid")).must_be :nil?
        end

        it "handles nil code" do
          _(Officer.find(nil)).must_be :nil?
        end

        it "handles empty code" do
          _(Officer.find("")).must_be :nil?
        end
      end

      describe "numeric qualification levels with real data" do
        before do
          # Reset to use real data from the gem
          Officer.reset_data
        end

        it "finds codes with qualification level 0" do
          code = Officer.find("11M0")
          _(code).wont_be :nil?
          _(code.qualification_level).must_equal :"0"
          _(code.name).must_equal "Mobility commander"
        end

        it "finds codes with qualification level 1" do
          code = Officer.find("11M1")
          _(code).wont_be :nil?
          _(code.qualification_level).must_equal :"1"
          _(code.name).must_equal "Mobility pilot"
        end

        it "finds codes with qualification level 2" do
          code = Officer.find("11M2")
          _(code).wont_be :nil?
          _(code.qualification_level).must_equal :"2"
          _(code.name).must_equal "Mobility navigator"
        end

        it "finds codes with qualification level 3" do
          code = Officer.find("11M3")
          _(code).wont_be :nil?
          _(code.qualification_level).must_equal :"3"
          _(code.name).must_equal "Mobility air battle manager"
        end

        it "finds codes with qualification level 4" do
          code = Officer.find("11M4")
          _(code).wont_be :nil?
          _(code.qualification_level).must_equal :"4"
          _(code.name).must_equal "Mobility Pilot"
        end
      end
    end
  end
end
