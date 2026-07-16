# frozen_string_literal: true

require "test_helper"
require "date"
require "gov_codes/afsc"
require "gov_codes/afsc/officer"
require "gov_codes/afsc/releases"

module GovCodes
  module AFSC
    # Versioned officer lookups against the shipped DAFOCD index (31 Oct 2025).
    # The committed officer index MAY be asserted against.
    describe "Officer versioned lookup" do
      after { AFSC.reset_data(lookup: $LOAD_PATH) }

      it "resolves a specialty (X-form) code" do
        code = Officer.find("11MX")
        _(code).wont_be_nil
        _(code.specialty).must_equal :"11MX"
        _(code.specialty_name).must_equal "Mobility Pilot"
        _(code.name).must_equal "Mobility Pilot"
        _(code.effective_date).must_equal Date.new(2025, 10, 31)
      end

      it "derives the specialty from a concrete qualification level" do
        code = Officer.find("11B3")
        _(code.specialty).must_equal :"11BX"
        _(code.specialty_name).must_equal "Bomber Pilot"
        _(code.qualification_level).must_equal :"3"
        _(code.qualification_level_number).must_equal 3
        _(code.qualification_level_name).must_equal "Aircraft Commander"
        # No shredout: name falls back to the specialty name.
        _(code.name).must_equal "Bomber Pilot"
      end

      it "falls back to the standard qualification-level title when the release omits it" do
        qualified = Officer.find("11G3")
        _(qualified.qualification_level_name).must_equal "Qualified"

        staff = Officer.find("11G4")
        _(staff.qualification_level_name).must_equal "Staff"
      end

      it "resolves a literal bare code" do
        code = Officer.find("10C0")
        _(code).wont_be_nil
        _(code.specialty).must_equal :"10C0"
        _(code.name).must_equal "Operations Commander"
        _(code.effective_date).must_equal Date.new(2025, 10, 31)
      end

      it "resolves a shredout name as the deepest name" do
        code = Officer.find("11BXA")
        _(code.shredout).must_equal :A
        _(code.shredout_name).must_equal "B-1"
        _(code.name).must_equal "B-1"
      end

      it "resolves a shredout acronym over the specialty acronym" do
        code = Officer.find("19ZXB")
        _(code.acronym).must_equal "TACPO"
      end

      it "resolves the specialty acronym for a concrete code" do
        _(Officer.find("16F3").acronym).must_equal "FAO"
      end

      it "carries a nil acronym for a specialty without one" do
        _(Officer.find("11BX").acronym).must_be_nil
      end

      it "returns nil for an as_of before the earliest release" do
        _(Officer.find("11MX", as_of: "2000-01-01")).must_be_nil
      end

      it "returns nil for an unknown officer code" do
        _(Officer.find("99QX")).must_be_nil
      end

      it "raises a clear ArgumentError for an invalid as_of" do
        error = _ { Officer.find("11MX", as_of: "not-a-date") }.must_raise ArgumentError
        _(error.message).must_include "not-a-date"
      end

      it "shares a cache slot for equivalent as_of values" do
        latest = Releases.effective_date_for(as_of: nil, publication: Releases::OFFICER_PUBLICATION)
        by_nil = Officer.find("11MX")
        by_date = Officer.find("11MX", as_of: latest)
        by_string = Officer.find("11MX", as_of: latest.to_s)

        _(by_date).must_be_same_as by_nil
        _(by_string).must_be_same_as by_nil
      end
    end

    describe "Officer.search over the versioned index" do
      after { AFSC.reset_data(lookup: $LOAD_PATH) }

      it "emits the specialty and its shredout suffixes" do
        codes = Officer.search("11BX").map { |c| "#{c.specific_afsc}#{c.shredout}" }
        _(codes).must_include "11BX"
        _(codes).must_include "11BXA"
      end

      it "is case-insensitive" do
        _(Officer.search("11bx").map(&:specialty)).must_include :"11BX"
      end

      it "returns an empty array for an as_of before the earliest release" do
        _(Officer.search("11BX", as_of: "1900-01-01")).must_equal []
      end
    end

    describe "Officer.find_by_acronym" do
      after { AFSC.reset_data(lookup: $LOAD_PATH) }

      it "resolves a specialty by its acronym (canonical first match)" do
        code = Officer.find_by_acronym("FAO")
        _(code.specialty).must_equal :"16FX"
      end

      it "is case-insensitive" do
        _(Officer.find_by_acronym("fao").specialty).must_equal :"16FX"
      end

      it "resolves a shredout acronym to the concrete shredded code" do
        code = Officer.find_by_acronym("TACPO")
        _(code).must_equal Officer.find("19ZXB")
        _(code.specialty).must_equal :"19ZX"
        _(code.shredout).must_equal :B
        _(code.acronym).must_equal "TACPO"
      end

      it "returns nil for an unknown or empty acronym" do
        _(Officer.find_by_acronym("ZZZZ")).must_be_nil
        _(Officer.find_by_acronym("")).must_be_nil
      end
    end
  end
end
