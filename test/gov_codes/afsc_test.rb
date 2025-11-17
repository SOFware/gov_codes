require "test_helper"
require "gov_codes/afsc"
require "gov_codes/afsc/enlisted"
require "gov_codes/afsc/officer"

module GovCodes
  class AFSCTest < Minitest::Test
    def test_find_returns_enlisted_code_for_valid_enlisted_afsc
      # Test with a valid enlisted AFSC code
      code = AFSC.find("1A1X2")

      # Verify it returns an Enlisted::Code object
      assert_instance_of GovCodes::AFSC::Enlisted::Code, code

      # Verify the properties are correctly set
      assert_equal :"1", code.career_group
      assert_equal :"1A", code.career_field
      assert_equal :"1A1", code.career_field_subdivision
      assert_equal :X, code.skill_level
      assert_equal :"1A1X2", code.specific_afsc
      assert_nil code.shredout
      assert_equal "Mobility force aviator", code.name
    end

    def test_find_returns_officer_code_for_valid_officer_afsc
      # Test with a valid officer AFSC code (from Wikipedia)
      code = AFSC.find("11MX")

      # Verify it returns an Officer::Code object
      assert_instance_of GovCodes::AFSC::Officer::Code, code

      # Verify the properties are correctly set
      assert_nil code.prefix
      assert_equal :"11", code.career_group
      assert_equal :M, code.functional_area
      assert_equal :X, code.qualification_level
      assert_nil code.shredout
      assert_equal "Mobility pilot", code.name
    end

    def test_find_raises_error_for_invalid_afsc
      # Test with an invalid AFSC code
      assert_nil AFSC.find("invalid")
    end

    def test_search_returns_array_of_codes
      results = AFSC.search("1Z1")

      assert_instance_of Array, results
      refute_empty results

      # Should find Pararescue (1Z1X1)
      codes = results.map { |r| r.specific_afsc.to_s }
      assert_includes codes, "1Z1X1"
    end

    def test_search_finds_enlisted_codes
      results = AFSC.search("1A1X2")

      refute_empty results

      # All results should be Enlisted::Code objects
      results.each do |code|
        assert_instance_of GovCodes::AFSC::Enlisted::Code, code
      end

      # Should find the base code and shredouts
      codes = results.map { |r| "#{r.specific_afsc}#{r.shredout}" }
      assert_includes codes, "1A1X2"
      assert_includes codes, "1A1X2A" # C-5 flight engineer
    end

    def test_search_finds_officer_codes
      results = AFSC.search("11BX")

      refute_empty results

      # All results should be Officer::Code objects
      results.each do |code|
        assert_instance_of GovCodes::AFSC::Officer::Code, code
      end

      # Should find the base code and shredouts
      codes = results.map { |r| "#{r.specific_afsc}#{r.shredout}" }
      assert_includes codes, "11BX"
      assert_includes codes, "11BXA" # B-1
    end

    def test_search_finds_ri_codes
      results = AFSC.search("8G")

      refute_empty results

      # Should find RI codes
      ri_results = results.select { |r| r.is_a?(GovCodes::AFSC::RI::Code) }
      refute_empty ri_results

      # Should find 8G000 and its suffixes
      codes = ri_results.map { |r| "#{r.specific_ri}#{r.suffix}" }
      assert_includes codes, "8G000"
      assert_includes codes, "8G000B" # Pallbearer
    end

    def test_search_returns_empty_array_for_no_matches
      results = AFSC.search("ZZZ")

      assert_instance_of Array, results
      assert_empty results
    end

    def test_search_is_case_insensitive
      results_upper = AFSC.search("1Z1")
      results_lower = AFSC.search("1z1")

      assert_equal results_upper.map(&:name), results_lower.map(&:name)
    end
  end
end
