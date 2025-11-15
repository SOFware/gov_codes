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

        # Create a sample YAML file with test data matching new structure
        File.write(@temp_yaml_path, <<~YAML)
          11BX:
            name: Test Operations Officer
            subcategories:
              A: Test Shredout A
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
          _(data[:"11BX"]).wont_be :nil?
          _(data.dig(:"11BX", :name)).must_equal "Test Operations Officer"
        end

        it "works with custom lookup path" do
          data = Officer.data(lookup: [@temp_dir])
          _(data.dig(:"11BX", :name)).must_equal "Test Operations Officer"
        end
      end

      describe "#find" do
        it "finds valid code" do
          # Use reset_data with custom lookup to override the real data
          Officer.reset_data(lookup: [@temp_dir])

          code = Officer.find("11BX")

          _(code).wont_be :nil?
          _(code.career_group).must_equal :"11"
          _(code.functional_area).must_equal :B
          _(code.qualification_level).must_equal :X
          _(code.shredout).must_be :nil?
          _(code.name).must_equal "Test Operations Officer"
        end

        it "finds code with shredout" do
          # Use reset_data with custom lookup to override the real data
          Officer.reset_data(lookup: [@temp_dir])

          code = Officer.find("11BXA")

          _(code).wont_be :nil?
          _(code.shredout).must_equal :A
          _(code.name).must_equal "Test Shredout A"
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
    end
  end
end
