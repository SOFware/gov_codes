# frozen_string_literal: true

require "test_helper"
require "date"
require "gov_codes/afsc"
require "gov_codes/afsc/ri"
require "gov_codes/afsc/releases"

module GovCodes
  module AFSC
    # RI/SDI (Reporting Identifiers / Special Duty Identifiers) resolved against
    # the shipped, versioned DAFECD (enlisted, 5-char) and DAFOCD (officer,
    # 4-char) release indexes (both effective 31 Oct 2025). The committed ri.yml
    # artifacts MAY be asserted against directly.
    describe RI do
      after { AFSC.reset_data(lookup: $LOAD_PATH) }

      describe "Parser" do
        it "decomposes a 5-char enlisted-shape code" do
          result = RI::Parser.new("9Z200").parse
          _(result[:career_group]).must_equal :"9"
          _(result[:career_field]).must_equal :"9Z"
          _(result[:identifier]).must_equal :"200"
          _(result[:suffix]).must_be_nil
          _(result[:specific_ri]).must_equal :"9Z200"
          _(result[:publication]).must_equal Releases::ENLISTED_PUBLICATION
        end

        it "decomposes a 5-char enlisted-shape code with a suffix" do
          result = RI::Parser.new("8G000B").parse
          _(result[:career_group]).must_equal :"8"
          _(result[:career_field]).must_equal :"8G"
          _(result[:identifier]).must_equal :"000"
          _(result[:suffix]).must_equal :B
          _(result[:specific_ri]).must_equal :"8G000"
          _(result[:publication]).must_equal Releases::ENLISTED_PUBLICATION
        end

        it "decomposes a 4-char officer-shape code (identifier is one digit)" do
          result = RI::Parser.new("90G0").parse
          _(result[:career_group]).must_equal :"90"
          _(result[:career_field]).must_equal :"90G"
          _(result[:identifier]).must_equal :"0"
          _(result[:suffix]).must_be_nil
          _(result[:specific_ri]).must_equal :"90G0"
          _(result[:publication]).must_equal Releases::OFFICER_PUBLICATION
        end

        it "returns nil fields and publication for an unparseable code" do
          result = RI::Parser.new("invalid").parse
          _(result[:career_group]).must_be_nil
          _(result[:specific_ri]).must_be_nil
          _(result[:publication]).must_be_nil
        end
      end

      describe "#find (enlisted shape)" do
        it "resolves a base enlisted RI/SDI code from the shipped index" do
          code = RI.find("9Z200")
          _(code).wont_be_nil
          _(code).must_be_instance_of RI::Code
          _(code.specific_ri).must_equal :"9Z200"
          _(code.career_group).must_equal :"9"
          _(code.career_field).must_equal :"9Z"
          _(code.identifier).must_equal :"200"
          _(code.suffix).must_be_nil
          _(code.name).must_equal "Special Warfare Mission Support (SWMS) " \
            "Superintendent, Air Force Special Warfare (AFSPECWAR)"
          _(code.effective_date).must_equal Date.new(2025, 10, 31)
        end

        it "resolves a shredout suffix meaning from the entry" do
          code = RI.find("8G000B")
          _(code.specific_ri).must_equal :"8G000"
          _(code.suffix).must_equal :B
          _(code.name).must_equal "Pallbearer"
        end

        it "falls back to the base name when no suffix is given" do
          _(RI.find("8G000").name).must_equal "Premier Honor Guard"
        end

        it "resolves another shredout meaning" do
          _(RI.find("8R300A").name).must_equal "Flight Chief"
          _(RI.find("8R300").name).must_equal "Third-Tier Recruiter"
        end

        it "carries a source-verified acronym" do
          _(RI.find("9M200").acronym).must_equal "IHS"
          _(RI.find("8C000").acronym).must_equal "RNCO"
        end

        it "carries a nil acronym when the entry has none" do
          _(RI.find("8A400").acronym).must_be_nil
        end

        it "returns nil for an enlisted-shape code absent from the index" do
          _(RI.find("9Z999")).must_be_nil
        end
      end

      describe "#find (officer shape)" do
        it "resolves a 4-char officer RI/SDI code from the shipped index" do
          code = RI.find("90G0")
          _(code).wont_be_nil
          _(code).must_be_instance_of RI::Code
          _(code.specific_ri).must_equal :"90G0"
          _(code.career_group).must_equal :"90"
          _(code.career_field).must_equal :"90G"
          _(code.identifier).must_equal :"0"
          _(code.name).must_equal "General Officer"
          _(code.effective_date).must_equal Date.new(2025, 10, 31)
        end

        it "carries a source-verified officer acronym" do
          _(RI.find("88C0").acronym).must_equal "SARC"
        end

        it "returns nil for an officer-shape code absent from the index" do
          _(RI.find("99Z0")).must_be_nil
        end
      end

      describe "#find dispatch and validation" do
        it "returns nil for an unparseable code" do
          _(RI.find("invalid")).must_be_nil
        end

        it "shares a cache slot for equivalent as_of values" do
          by_nil = RI.find("9Z200")
          by_date = RI.find("9Z200", as_of: Date.new(2025, 10, 31))
          by_string = RI.find("9Z200", as_of: "2025-10-31")
          _(by_date).must_be_same_as by_nil
          _(by_string).must_be_same_as by_nil
        end

        it "returns nil before the earliest release and resolves at/after it" do
          _(RI.find("9Z200", as_of: "2000-01-01")).must_be_nil
          _(RI.find("9Z200", as_of: "2025-10-31")).wont_be_nil
          _(RI.find("9Z200", as_of: "2026-01-01")).wont_be_nil
        end

        it "raises a clear ArgumentError for an invalid as_of" do
          error = _ { RI.find("9Z200", as_of: "not-a-date") }.must_raise ArgumentError
          _(error.message).must_include "not-a-date"
        end
      end

      # A single RI.find / AFSC.find entry point dispatches by code shape to the
      # correct publication: 5-char -> DAFECD (enlisted), 4-char -> DAFOCD.
      describe "shape-based dispatch through one entry point" do
        it "resolves both shapes through RI.find" do
          _(RI.find("9Z200").name).must_equal "Special Warfare Mission Support " \
            "(SWMS) Superintendent, Air Force Special Warfare (AFSPECWAR)"
          _(RI.find("90G0").name).must_equal "General Officer"
        end

        it "resolves both shapes through AFSC.find as RI::Code" do
          enlisted_shape = AFSC.find("9Z200")
          officer_shape = AFSC.find("90G0")
          _(enlisted_shape).must_be_instance_of RI::Code
          _(officer_shape).must_be_instance_of RI::Code
          _(enlisted_shape.specific_ri).must_equal :"9Z200"
          _(officer_shape.specific_ri).must_equal :"90G0"
        end
      end

      describe "#find_by_acronym" do
        it "resolves an enlisted RI acronym (forward + reverse agree)" do
          _(RI.find("9M200").acronym).must_equal "IHS"
          code = RI.find_by_acronym("IHS")
          _(code.specific_ri).must_equal :"9M200"
          _(code.name).must_equal "International Health Specialists (IHS)"
        end

        it "resolves an officer RI acronym" do
          code = RI.find_by_acronym("SARC")
          _(code.specific_ri).must_equal :"88C0"
        end

        it "is case-insensitive" do
          _(RI.find_by_acronym("sarc").specific_ri).must_equal :"88C0"
        end

        it "searches enlisted before officer for a shared acronym" do
          # LAS is both 9W400 (enlisted) and 92W4 (officer); enlisted wins.
          _(RI.find_by_acronym("LAS").specific_ri).must_equal :"9W400"
        end

        it "returns nil for an unknown or empty acronym" do
          _(RI.find_by_acronym("ZZZZ")).must_be_nil
          _(RI.find_by_acronym("")).must_be_nil
        end
      end

      describe "#search" do
        it "emits an enlisted base code and its shredout suffixes" do
          codes = RI.search("8G").map { |c| "#{c.specific_ri}#{c.suffix}" }
          _(codes).must_include "8G000"
          _(codes).must_include "8G000B"
        end

        it "emits officer codes" do
          codes = RI.search("90G").map { |c| c.specific_ri.to_s }
          _(codes).must_include "90G0"
        end

        it "walks both publications for a shared prefix" do
          codes = RI.search("8").map { |c| c.specific_ri.to_s }
          _(codes).must_include "8G000" # enlisted
          _(codes).must_include "80C0"  # officer
        end

        it "is case-insensitive" do
          _(RI.search("8g").map(&:name)).must_equal RI.search("8G").map(&:name)
        end

        it "returns an empty array before the earliest release" do
          _(RI.search("8G", as_of: "1900-01-01")).must_equal []
        end
      end
    end
  end
end
