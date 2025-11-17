# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

module GovCodes
  module AFSC
    describe RI do
      before do
        # Create a temporary directory for our test YAML file
        @temp_dir = Dir.mktmpdir
        @gov_codes_dir = File.join(@temp_dir, "gov_codes", "afsc")
        FileUtils.mkdir_p(@gov_codes_dir)
        @temp_yaml_path = File.join(@gov_codes_dir, "ri.yml")

        # Create a sample YAML file with test data
        File.write(@temp_yaml_path, <<~YAML)
          :9Z:
            :name: Test Special Duty
            :subcategories:
              :000: Test identifier zero
              :100: Test identifier one
              :200:
                :name: Test identifier two
                :subcategories:
                  :A: Test suffix A
                  :B: Test suffix B
        YAML
      end

      after do
        # Clean up the temporary directory
        FileUtils.rm_rf(@temp_dir)
      end

      describe "#data" do
        it "merges YAML files from lookup path" do
          data = RI.data(lookup: [@temp_dir])

          _(data[:"9Z"]).wont_be :nil?
          _(data.dig(:"9Z", :name)).must_equal "Test Special Duty"
          _(data.dig(:"9Z", :subcategories, :"000")).must_equal "Test identifier zero"
          _(data.dig(:"9Z", :subcategories, :"200", :name)).must_equal "Test identifier two"
          _(data.dig(:"9Z", :subcategories, :"200", :subcategories, :A)).must_equal "Test suffix A"
        end
      end

      describe "#find" do
        before do
          RI.reset_data(lookup: [@temp_dir])
        end

        it "finds a simple RI code" do
          code = RI.find("9Z000")
          _(code).wont_be :nil?
          _(code.specific_ri.to_s).must_equal "9Z000"
          _(code.name).must_equal "Test identifier zero"
          _(code.career_group.to_s).must_equal "9"
          _(code.career_field.to_s).must_equal "9Z"
          _(code.identifier.to_s).must_equal "000"
          _(code.suffix).must_be :nil?
        end

        it "finds an RI code with nested name" do
          code = RI.find("9Z200")
          _(code).wont_be :nil?
          _(code.specific_ri.to_s).must_equal "9Z200"
          _(code.name).must_equal "Test identifier two"
        end

        it "finds an RI code with suffix" do
          code = RI.find("9Z200A")
          _(code).wont_be :nil?
          _(code.specific_ri.to_s).must_equal "9Z200"
          _(code.suffix.to_s).must_equal "A"
          _(code.name).must_equal "Test suffix A"
        end

        it "returns nil for unknown codes" do
          code = RI.find("9Z999")
          _(code).must_be :nil?
        end

        it "returns nil for invalid format" do
          code = RI.find("invalid")
          _(code).must_be :nil?
        end
      end

      describe "Parser" do
        it "parses basic RI code" do
          parser = RI::Parser.new("9Z200")
          result = parser.parse

          _(result[:career_group]).must_equal :"9"
          _(result[:career_field]).must_equal :"9Z"
          _(result[:identifier]).must_equal :"200"
          _(result[:suffix]).must_be :nil?
          _(result[:specific_ri]).must_equal :"9Z200"
        end

        it "parses RI code with suffix" do
          parser = RI::Parser.new("8G000B")
          result = parser.parse

          _(result[:career_group]).must_equal :"8"
          _(result[:career_field]).must_equal :"8G"
          _(result[:identifier]).must_equal :"000"
          _(result[:suffix]).must_equal :B
          _(result[:specific_ri]).must_equal :"8G000"
        end

        it "handles 8X series codes" do
          parser = RI::Parser.new("8A400")
          result = parser.parse

          _(result[:career_group]).must_equal :"8"
          _(result[:career_field]).must_equal :"8A"
          _(result[:identifier]).must_equal :"400"
        end

        it "returns nil fields for invalid code" do
          parser = RI::Parser.new("invalid")
          result = parser.parse

          _(result[:career_group]).must_be :nil?
          _(result[:specific_ri]).must_be :nil?
        end
      end
    end
  end
end
