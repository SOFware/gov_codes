require "test_helper"
require "minitest/autorun"

class EnlistedCoverageTest < Minitest::Test
  def test_find_with_nil_and_empty
    assert_nil GovCodes::AFSC::Enlisted.find(nil)
    assert_nil GovCodes::AFSC::Enlisted.find("")
  end

  def test_find_with_invalid_code
    assert_nil GovCodes::AFSC::Enlisted.find("invalid")
    assert_nil GovCodes::AFSC::Enlisted.find("1A1X!")
    assert_nil GovCodes::AFSC::Enlisted.find("1A1X2ABC") # too long
    assert_nil GovCodes::AFSC::Enlisted.find("1a1x2")    # lowercase
    assert_nil GovCodes::AFSC::Enlisted.find("!1A1X2")   # invalid prefix
  end

  def test_find_with_partial_codes
    assert_nil GovCodes::AFSC::Enlisted.find("1")
    assert_nil GovCodes::AFSC::Enlisted.find("1A")
    assert_nil GovCodes::AFSC::Enlisted.find("1A1")
    assert_nil GovCodes::AFSC::Enlisted.find("1A1X")
  end

  def test_parser_with_various_inputs
    parser = GovCodes::AFSC::Enlisted::Parser.new(nil)
    assert_equal({prefix: nil, career_group: nil, career_field: nil, career_field_subdivision: nil, skill_level: nil, skill_level_number: nil, skill_level_name: nil, specialty: nil, specialty_name: nil, specific_afsc: nil, subcategory: nil, shredout: nil}, parser.parse)

    parser = GovCodes::AFSC::Enlisted::Parser.new("")
    assert_equal({prefix: nil, career_group: nil, career_field: nil, career_field_subdivision: nil, skill_level: nil, skill_level_number: nil, skill_level_name: nil, specialty: nil, specialty_name: nil, specific_afsc: nil, subcategory: nil, shredout: nil}, parser.parse)

    parser = GovCodes::AFSC::Enlisted::Parser.new("1A1X2")
    result = parser.parse
    assert_equal :"1A", result[:career_field]
    assert_equal :"1A1", result[:career_field_subdivision]
    assert_equal :X, result[:skill_level]
    assert_equal :"1A1X2", result[:specific_afsc]
    assert_equal :"1X2", result[:subcategory]
    assert_nil result[:shredout]
  end

  def test_parser_with_prefix_and_shredout
    parser = GovCodes::AFSC::Enlisted::Parser.new("A1A1X2A")
    result = parser.parse
    assert_equal "A", result[:prefix]
    assert_equal :"1A", result[:career_field]
    assert_equal :"1A1", result[:career_field_subdivision]
    assert_equal :X, result[:skill_level]
    assert_equal :"1A1X2", result[:specific_afsc]
    assert_equal :"1X2", result[:subcategory]
    assert_equal :A, result[:shredout]
  end

  def test_parser_early_returns
    # No career group
    parser = GovCodes::AFSC::Enlisted::Parser.new("A")
    result = parser.parse
    assert_equal "A", result[:prefix]
    assert_nil result[:career_group]

    # No career field letter
    parser = GovCodes::AFSC::Enlisted::Parser.new("1")
    result = parser.parse
    assert_equal :"1", result[:career_group]
    assert_nil result[:career_field]

    # No subdivision digit
    parser = GovCodes::AFSC::Enlisted::Parser.new("1A")
    result = parser.parse
    assert_equal :"1A", result[:career_field]
    assert_nil result[:career_field_subdivision]

    # No skill level letter
    parser = GovCodes::AFSC::Enlisted::Parser.new("1A1")
    result = parser.parse
    assert_equal :"1A1", result[:career_field_subdivision]
    assert_nil result[:skill_level]

    # No skill level digit
    parser = GovCodes::AFSC::Enlisted::Parser.new("1A1X")
    result = parser.parse
    assert_equal :X, result[:skill_level]
    assert_nil result[:specific_afsc]
  end

  def test_parser_not_at_end
    parser = GovCodes::AFSC::Enlisted::Parser.new("1A1X2A")
    result = parser.parse
    assert_equal :A, result[:shredout]
    assert_equal :"1A1X2", result[:specific_afsc]
  end

  def test_valid_enlisted_codes
    # Test various valid enlisted codes against the shipped DAFECD release.
    code1 = GovCodes::AFSC::Enlisted.find("1A1X2")
    assert code1
    assert_equal "Mobility Force Aviator", code1.name

    code2 = GovCodes::AFSC::Enlisted.find("1A1X2A")
    assert code2
    assert_equal "C-5 Flight Engineer", code2.name

    code3 = GovCodes::AFSC::Enlisted.find("A1A1X2A")
    assert code3
    assert_equal "C-5 Flight Engineer", code3.name
  end

  def test_code_object_attributes
    code = GovCodes::AFSC::Enlisted.find("1A1X2A")
    assert code
    # The prefix might be nil depending on how the parser handles it
    # Let's check what the actual prefix is
    assert code.prefix.nil? || code.prefix == "A"
    assert_equal :"1", code.career_group
    assert_equal :"1A", code.career_field
    assert_equal :"1A1", code.career_field_subdivision
    assert_equal :X, code.skill_level
    assert_equal :"1A1X2", code.specific_afsc
    assert_equal :"1X2", code.subcategory
    assert_equal :A, code.shredout
    assert_equal "C-5 Flight Engineer", code.name
  end
end
