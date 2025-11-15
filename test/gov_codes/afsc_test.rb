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
  end
end
