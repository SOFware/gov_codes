# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

module GovCodes
  module AFSC
    describe Enlisted do
      before do
        # Create a temporary directory for our test YAML file
        @temp_dir = Dir.mktmpdir
        @gov_codes_dir = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(@gov_codes_dir)
        @temp_yaml_path = File.join(@gov_codes_dir, "enlisted.yml")

        # Create a sample YAML file with test data
        File.write(@temp_yaml_path, <<~YAML)
          9Z:
            name: Test Operations
            subcategories:
              0X1:
                name: Test Operations Group
                subcategories:
                  A:
                    name: Test Operations Apprentice
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
          data = Enlisted.data(lookup: [$LOAD_PATH.first])

          # Verify that our test data is present
          _(data[:"9Z"]).wont_be :nil?
          _(data.dig(:"9Z", :name)).must_equal "Test Operations"
          _(data.dig(:"9Z", :subcategories, :"0X1")).wont_be :nil?
          _(data.dig(:"9Z", :subcategories, :"0X1", :name)).must_equal "Test Operations Group"
          _(data.dig(:"9Z", :subcategories, :"0X1", :subcategories, :A)).wont_be :nil?
          _(data.dig(:"9Z", :subcategories, :"0X1", :subcategories, :A, :name)).must_equal "Test Operations Apprentice"
        end

        it "works with custom lookup path" do
          data = Enlisted.data(lookup: [@temp_dir])
          _(data.dig(:"9Z", :name)).must_equal "Test Operations"
          _(data.dig(:"9Z", :subcategories, :"0X1")).wont_be :nil?
          _(data.dig(:"9Z", :subcategories, :"0X1", :name)).must_equal "Test Operations Group"
          _(data.dig(:"9Z", :subcategories, :"0X1", :subcategories, :A)).wont_be :nil?
          _(data.dig(:"9Z", :subcategories, :"0X1", :subcategories, :A, :name)).must_equal "Test Operations Apprentice"
        end
      end

      describe "#find" do
        it "uses merged data" do
          Enlisted.reset_data
          code = Enlisted.find("9Z0X1")
          _(code).wont_be :nil?
          _(code.specific_afsc.to_s).must_equal "9Z0X1"
          _(code.name).must_equal "Test Operations Group"
        end

        it "returns correct object" do
          AFSC.reset_data
          code = Enlisted.find("9Z0X1")
          _(code.specific_afsc.to_s).must_equal "9Z0X1"
          _(code.name).must_equal "Test Operations Group"
        end
      end
    end
  end
end
