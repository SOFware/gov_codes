# frozen_string_literal: true

require "test_helper"

module GovCodes
  module AFSC
    describe Enlisted::Parser do
      it "parses a concrete skill-level code" do
        result = Enlisted::Parser.new("1A172").parse
        _(result[:career_field]).must_equal :"1A"
        _(result[:career_field_subdivision]).must_equal :"1A1"
        _(result[:skill_level]).must_equal :"7"
        _(result[:skill_level_number]).must_equal 7
        _(result[:skill_level_name]).must_equal "Craftsman"
        _(result[:specialty]).must_equal :"1A1X2"
        _(result[:subcategory]).must_equal :"1X2"
        _(result[:specific_afsc]).must_equal :"1A172"
      end

      it "still parses the generic X-form unchanged" do
        result = Enlisted::Parser.new("1A1X2").parse
        _(result[:skill_level]).must_equal :X
        _(result[:skill_level_number]).must_be_nil
        _(result[:skill_level_name]).must_be_nil
        _(result[:specialty]).must_equal :"1A1X2"
        _(result[:subcategory]).must_equal :"1X2"
        _(result[:specific_afsc]).must_equal :"1A1X2"
      end

      it "parses a concrete code with a shredout" do
        result = Enlisted::Parser.new("1A172Y").parse
        _(result[:skill_level_number]).must_equal 7
        _(result[:shredout]).must_equal :Y
        _(result[:specialty]).must_equal :"1A1X2"
      end
    end

    describe "Enlisted.find with concrete codes" do
      it "resolves a concrete skill-level code to specialty details" do
        code = Enlisted.find("1A172")
        _(code).wont_be_nil
        _(code.specialty).must_equal :"1A1X2"
        _(code.specialty_name).must_equal "Mobility Force Aviator"
        _(code.skill_level_number).must_equal 7
        _(code.skill_level_name).must_equal "Craftsman"
        _(code.specific_afsc).must_equal :"1A172"
      end

      it "keeps name and skill_level backward compatible for the generic form" do
        code = Enlisted.find("1A1X2")
        _(code.name).must_equal "Mobility Force Aviator"
        _(code.skill_level).must_equal :X
        _(code.specialty_name).must_equal "Mobility Force Aviator"
      end

      it "exposes shredout_name distinctly from specialty_name" do
        code = Enlisted.find("1A1X2A")
        _(code.specialty_name).must_equal "Mobility Force Aviator"
        _(code.shredout).must_equal :A
        _(code.shredout_name).must_equal "C-5 Flight Engineer"
        _(code.name).must_equal "C-5 Flight Engineer"
      end

      it "resolves a concrete code combined with a real shredout" do
        code = Enlisted.find("1A172A")
        _(code.skill_level_number).must_equal 7
        _(code.skill_level_name).must_equal "Craftsman"
        _(code.specialty).must_equal :"1A1X2"
        _(code.specialty_name).must_equal "Mobility Force Aviator"
        _(code.shredout).must_equal :A
        _(code.shredout_name).must_equal "C-5 Flight Engineer"
        _(code.name).must_equal "C-5 Flight Engineer" # deepest
      end

      it "falls back to the specialty when the shredout is not in the data" do
        # R is not a documented shredout for 1A1X2 in the DAFECD release.
        code = Enlisted.find("1A172R")
        _(code.shredout).must_equal :R
        _(code.shredout_name).must_be_nil
        _(code.name).must_equal "Mobility Force Aviator"
        _(code.skill_level_number).must_equal 7
      end
    end
  end
end
